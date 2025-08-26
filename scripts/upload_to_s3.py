import argparse, boto3, pathlib

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bucket", required=True)
    p.add_argument("--prefix", required=True, help="e.g., bronze/ecommerce/customers/ingestion_date=2025-08-21/")
    p.add_argument("files", nargs="+")
    args = p.parse_args()

    s3 = boto3.client("s3")
    for f in args.files:
        src = pathlib.Path(f)
        key = f"{args.prefix.rstrip('/')}/{src.name}"
        print(f"Uploading {src} -> s3://{args.bucket}/{key}")
        s3.upload_file(str(src), args.bucket, key)

if __name__ == "__main__":
    main()
