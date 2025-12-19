import json
import os
from google.cloud import pubsub_v1, storage
from faster_whisper import WhisperModel

# --- CONFIGURATION ---
# Use the actual values from your terraform output
PROJECT_ID = "acoustic-alpha-308609"
SUBSCRIPTION_ID = "sub-transcribe-gpu-worker-fc941405"
BUCKET_NAME = "whisper-media-pipeline-fc941405"
MODEL_SIZE = "medium"

def process_message(message):
    """
    Callback function that processes individual Pub/Sub messages.
    """
    print(f"📥 Received message: {message.message_id}")
    
    try:
        # 1. Parse GCS Notification data
        data = json.loads(message.data.decode("utf-8"))
        object_id = data.get("name")
        bucket_name = data.get("bucket", BUCKET_NAME)

        # 2. Filter for .wav files (as defined in your latest main.tf)
        if not object_id or not object_id.endswith(".wav"):
            print(f"⏩ Skipping {object_id}: Not a .wav file.")
            message.ack()
            return

        print(f"🎧 Processing Audio: {object_id}")
        
        # 3. Setup Storage client and download the file
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        
        local_audio_path = f"/tmp/{os.path.basename(object_id)}"
        bucket.blob(object_id).download_to_filename(local_audio_path)
        
        # 4. Load Faster-Whisper Model and Transcribe
        # Using device="cuda" and compute_type="float16" for L4 GPU optimization
        print(f"🧠 Loading model ({MODEL_SIZE}) and transcribing...")
        model = WhisperModel(MODEL_SIZE, device="cuda", compute_type="float16")
        
        segments, info = model.transcribe(local_audio_path, beam_size=5)
        
        # Combine all transcribed segments into a single string
        full_text = " ".join([segment.text for segment in segments])
        
        # 5. Upload Transcription back to the same bucket
        transcription_path = object_id.replace(".wav", "_transcription.txt")
        output_blob = bucket.blob(transcription_path)
        output_blob.upload_from_string(full_text)
        
        print(f"✅ Saved transcription to: {transcription_path}")
        
        # 6. Acknowledge the message to pull the next file from the queue
        message.ack()

    except Exception as e:
        print(f"❌ Error processing {object_id if 'object_id' in locals() else 'unknown'}: {e}")
        # Nack tells Pub/Sub to put the message back in the queue for another attempt
        message.nack()

def main():
    """
    Initializes the Subscriber and begins listening for messages.
    """
    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(PROJECT_ID, SUBSCRIPTION_ID)
    
    # FLOW CONTROL: Ensures the worker only pulls 1 message at a time.
    # The worker will wait until the current job finishes and message.ack() is called 
    # before picking up the next file in the queue.
    flow_control = pubsub_v1.types.FlowControl(max_messages=1)
    
    streaming_pull_future = subscriber.subscribe(
        subscription_path, 
        callback=process_message,
        flow_control=flow_control
    )

    print(f"👀 Worker listening on: {subscription_path}")
    
    # Keep the main thread alive while listening
    try:
        streaming_pull_future.result()
    except KeyboardInterrupt:
        streaming_pull_future.cancel()
        print("\nShutting down worker...")

if __name__ == "__main__":
    main()