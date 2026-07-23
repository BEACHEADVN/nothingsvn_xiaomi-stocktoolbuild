import os
import pickle
import sys
import argparse
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from google.auth.transport.requests import Request

# Scopes needed for Drive API (Uploading files)
SCOPES = ['https://www.googleapis.com/auth/drive.file']

def get_credentials():
    creds = None
    # Adjust path if token.pickle is in a different directory
    token_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'token.pickle')
    if os.path.exists(token_path):
        with open(token_path, 'rb') as token:
            creds = pickle.load(token)
            
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            print("Refreshing access token...")
            creds.refresh(Request())
            with open(token_path, 'wb') as token:
                pickle.dump(creds, token)
        else:
            print(f"Error: Invalid or missing token.pickle at {token_path}. Please generate it first.")
            sys.exit(1)
            
    return creds

def get_or_create_folder(service, folder_name, parent_id=None):
    query = f"name='{folder_name}' and mimeType='application/vnd.google-apps.folder' and trashed=false"
    if parent_id:
        query += f" and '{parent_id}' in parents"
        
    results = service.files().list(q=query, spaces='drive', fields='files(id, name)').execute()
    files = results.get('files', [])
    
    if files:
        return files[0].get('id')
    else:
        file_metadata = {
            'name': folder_name,
            'mimeType': 'application/vnd.google-apps.folder'
        }
        if parent_id:
            file_metadata['parents'] = [parent_id]
        folder = service.files().create(body=file_metadata, fields='id').execute()
        return folder.get('id')

def resolve_path(service, path, root_folder_id=None):
    if not path:
        return root_folder_id
        
    parts = [p for p in path.split('/') if p]
    current_parent = root_folder_id
    
    for part in parts:
        current_parent = get_or_create_folder(service, part, current_parent)
        
    return current_parent

def upload_rom(file_path, folder_id=None, path=None):
    if not os.path.exists(file_path):
        print(f"Error: The file '{file_path}' does not exist.")
        sys.exit(1)

    creds = get_credentials()
    
    try:
        service = build('drive', 'v3', credentials=creds)
        
        # Resolve path to get final folder ID
        final_folder_id = resolve_path(service, path, folder_id)

        file_name = os.path.basename(file_path)
        file_metadata = {'name': file_name}
        
        if final_folder_id:
            file_metadata['parents'] = [final_folder_id]

        print(f"Preparing to upload: {file_name}")
        
        media = MediaFileUpload(file_path, resumable=True)
        
        request = service.files().create(body=file_metadata,
                                         media_body=media,
                                         fields='id')
        
        response = None
        while response is None:
            status, response = request.next_chunk()
            if status:
                print(f"Uploaded {int(status.progress() * 100)}%")
                
        print(f"Upload Complete! File ID: {response.get('id')}")
        return response.get('id')
        
    except Exception as e:
        print(f"An error occurred during upload: {e}")
        sys.exit(1)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Upload a file to Google Drive.')
    parser.add_argument('file_path', help='Path to the file to upload')
    parser.add_argument('--folder_id', help='Google Drive Root Folder ID', default=None)
    parser.add_argument('--path', help='Path to create inside root folder', default=None)
    
    args = parser.parse_args()
    upload_rom(args.file_path, args.folder_id, args.path)
