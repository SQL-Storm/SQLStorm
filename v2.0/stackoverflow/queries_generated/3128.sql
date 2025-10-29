-- {"query": "3128.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2359} 

WITH UserStats AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score, 0))         AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeInfo AS (
    SELECT
        b.UserId,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)    AS HasGold,
        MAX(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS HasTagBadge,
        COUNT(*)                                        AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count                AS TagUseCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
PostDetails AS (
    SELECT
        p.Id                                    AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.OwnerUserId,
        COALESCE(p.AcceptedAnswerId, -1)        AS AcceptedAnswerId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId = 1   -- only questions
),
Combined AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.RepRank,
        bi.HasGold,
        bi.HasTagBadge,
        bi.BadgeCount,
        pd.PostId,
        pd.Title,
        pd.Score,
        pd.UpVoteCount,
        pd.DownVoteCount,
        pd.UserPostRank,
        COALESCE(pd.Tags, '')                AS RawTags,
        CASE WHEN pd.AcceptedAnswerId = -1 THEN NULL ELSE pd.AcceptedAnswerId END AS AcceptedAnswerId,
        tt.TagName,
        tt.TagUseCount,
        tt.TagRank
    FROM UserStats us
    LEFT JOIN BadgeInfo bi   ON bi.UserId = us.UserId
    LEFT JOIN PostDetails pd ON pd.OwnerUserId = us.UserId
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM pd.RawTags), '><')) AS TagName
    ) ptags ON true
    LEFT JOIN TopTags tt ON tt.TagName = ptags.TagName
    WHERE (us.Reputation > 50000 OR bi.HasGold = 1)
      AND (pd.Score IS NULL OR pd.Score >= 0)
)
SELECT
    CONCAT(Combined.DisplayName,
           ' (Rep: ', COALESCE(CAST(Combined.Reputation AS VARCHAR), '0'), ')') AS UserLabel,
    Combined.RepRank,
    Combined.BadgeCount,
    CASE WHEN Combined.HasGold = 1 THEN 'Gold' ELSE 'NoGold' END AS GoldStatus,
    Combined.PostId,
    COALESCE(Combined.Title, '<no title>')          AS QuestionTitle,
    Combined.Score,
    Combined.UpVoteCount,
    Combined.DownVoteCount,
    Combined.UserPostRank,
    Combined.TagName,
    Combined.TagUseCount,
    Combined.TagRank,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM Votes v
            WHERE v.PostId = Combined.PostId
              AND v.VoteTypeId = 2
              AND v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
        ) THEN 'Trending'
        ELSE 'Stale'
    END                                            AS ActivityStatus
FROM Combined
WHERE Combined.UserPostRank <= 3
   OR (Combined.TagRank IS NOT NULL AND Combined.TagRank <= 5)
ORDER BY Combined.RepRank ASC
LIMIT 100

UNION ALL

SELECT
    '---'               AS UserLabel,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
WHERE NOT EXISTS (SELECT 1 FROM Combined);
