-- {"query": "44012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 818}
Here is an elaborate SQL query for performance benchmarking:

WITH cte AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        b.Id AS BadgeId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.TagBased AS IsBadgeTagBased,
        b.Date AS BadgeDate,
        ARRAY_AGG(DISTINCT pt.Name) AS PostTypes,
        ARRAY_AGG(DISTINCT lt.Name) AS LinkTypes,
        ARRAY_AGG(DISTINCT crt.Name) AS CloseReasonTypes,
        ARRAY_AGG(DISTINCT vt.Name) AS VoteTypes
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN LinkTypes lt ON ph.PostHistoryTypeId = lt.Id
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = crt.Id
    LEFT JOIN VoteTypes vt ON ph.PostHistoryTypeId = vt.Id
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        b.Id,
        b.Name,
        b.Class,
        b.TagBased,
        b.Date
)
SELECT
    PostId,
    PostTypeId,
    Score,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    IsClosed,
    IsCommunityOwned,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    Reputation,
    UpVotes,
    DownVotes,
    Views,
    BadgeId,
    BadgeName,
    BadgeClass,
    IsBadgeTagBased,
    BadgeDate,
    PostTypes,
    LinkTypes,
    CloseReasonTypes,
    VoteTypes
FROM cte
ORDER BY PostId DESC
LIMIT 1000;
