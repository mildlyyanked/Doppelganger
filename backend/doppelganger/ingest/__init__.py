"""Source connectors. Each maps one platform into MemoryItem[] behind the
`Connector` interface, so a broken crawler never touches the rest of the
engine and crawl<->official-API<->upload is a one-file swap."""
from .base import Connector, ConnectorResult
from .reddit import RedditConnector
from .upload import UploadConnector
from .youtube import YouTubeConnector
from .crawl import WebCrawlConnector
from .instagram import InstagramConnector

# Registry used by the poller / API to spin up sources by name.
REGISTRY: dict[str, type[Connector]] = {
    "reddit": RedditConnector,
    "youtube": YouTubeConnector,
    "web": WebCrawlConnector,
    "upload": UploadConnector,
    "instagram": InstagramConnector,
}

__all__ = [
    "Connector",
    "ConnectorResult",
    "RedditConnector",
    "UploadConnector",
    "YouTubeConnector",
    "WebCrawlConnector",
    "InstagramConnector",
    "REGISTRY",
]
