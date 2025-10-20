-- {"query": "44081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 185814, "output_tokens": 64675} 
WITH cte AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        b.Name AS Badge,
        b.Date AS BadgeDate,
        b.Class AS BadgeClass,
        b.TagBased AS BadgeTagBased,
        v.VoteTypeId,
        v.CreationDate AS VoteCreationDate,
        v.BountyAmount,
        c.Score AS CommentScore,
        c.CreationDate AS CommentCreationDate,
        pl.LinkTypeId,
        pl.CreationDate AS LinkCreationDate,
        ht.Name AS HistoryType,
        ht.Id AS HistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ph.Comment AS HistoryComment,
        ph.Text AS HistoryText,
        RANK() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS HistoryRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
)
SELECT
    Id,
    PostTypeId,
    OwnerUserId,
    Tags,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    ClosedDate,
    CommunityOwnedDate,
    Reputation,
    UserCreationDate,
    LastAccessDate,
    Views,
    UpVotes,
    DownVotes,
    Badge,
    BadgeDate,
    BadgeClass,
    BadgeTagBased,
    VoteTypeId,
    VoteCreationDate,
    BountyAmount,
    CommentScore,
    CommentCreationDate,
    LinkTypeId,
    LinkCreationDate,
    HistoryType,
    HistoryTypeId,
    HistoryCreationDate,
    HistoryComment,
    HistoryText
FROM cte
WHERE HistoryRank = 1
ORDER BY Id;