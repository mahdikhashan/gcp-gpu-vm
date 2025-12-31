import json
import os
import logging
from google.cloud import pubsub_v1, storage
from faster_whisper import WhisperModel

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

PROJECT_ID = "acoustic-alpha-308609"
SUBSCRIPTION_ID = "sub-transcribe-gpu-worker-fc941405"
BUCKET_NAME = "whisper-media-pipeline-fc941405"
MODEL_SIZE = "large-v3"

def process_message(message):
    logger.info(f"Received message: {message.message_id}")
    
    try:
        data = json.loads(message.data.decode("utf-8"))
        object_id = data.get("name")
        bucket_name = data.get("bucket", BUCKET_NAME)
        
        if not object_id or not object_id.endswith(".wav"):
            logger.info(f"Skipping {object_id}: Not a .wav file.")
            message.ack()
            return
        
        logger.info(f"Processing Audio: {object_id}")
        
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        
        local_audio_path = f"/tmp/{os.path.basename(object_id)}"
        bucket.blob(object_id).download_to_filename(local_audio_path)
        
        logger.info(f"Loading model ({MODEL_SIZE}) and transcribing...")
        model = WhisperModel(MODEL_SIZE, device="cuda", compute_type="float16")
        
        segments, info = model.transcribe(local_audio_path, beam_size=5)
        
        full_text = " ".join([segment.text for segment in segments])
        
        transcription_path = object_id.replace(".wav", "_transcription.txt")
        output_blob = bucket.blob(transcription_path)
        output_blob.upload_from_string(full_text)
        
        logger.info(f"Saved transcription to: {transcription_path}")
        
        message.ack()
    except Exception as e:
        logger.error(f"Error processing {object_id if 'object_id' in locals() else 'unknown'}: {e}")
        message.nack()

def main():
    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(PROJECT_ID, SUBSCRIPTION_ID)
    
    flow_control = pubsub_v1.types.FlowControl(max_messages=1)
    
    streaming_pull_future = subscriber.subscribe(
        subscription_path, 
        callback=process_message,
        flow_control=flow_control
    )
    logger.info(f"Worker listening on: {subscription_path}")
    
    try:
        streaming_pull_future.result()
    except KeyboardInterrupt:
        streaming_pull_future.cancel()
        logger.info("Shutting down worker...")

if __name__ == "__main__":
    main()
