-- {"query": "3095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2418} 

WITH TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS QuestionCount,
        SUM(p.ViewCount)                                         AS TotalViews,
        AVG(p.Score)                                             AS AvgScore,
        MAX(p.CreationDate)                                      AS LatestQuestionDate
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags LIKE '%'||t.TagName||'%'
    GROUP BY t.TagName
),

UserMetrics AS (
    SELECT
        u.Id                                    AS UserId,
        u.Reputation,
        COALESCE(b.GoldCount,   0)              AS GoldBadges,
        COALESCE(b.SilverCount, 0)              AS SilverBadges,
        COALESCE(b.BronzeCount, 0)              AS BronzeBadges,
        COALESCE(v.UpVoteCount,   0)            AS UpVotes,
        COALESCE(v.DownVoteCount, 0)            AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE p.PostTypeId = 1                       -- only questions
        GROUP BY UserId
    ) v ON v.UserId = u.Id
),

PostEngagement AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(c.CommentCount, 0)               AS CommentCount,
        COALESCE(v.UpVoteCount,   0)               AS UpVoteCount,
        COALESCE(v.DownVoteCount, 0)               AS DownVoteCount,
        (p.Score * 2
         + p.ViewCount / 10
         + COALESCE(c.CommentCount, 0) * 3
         + COALESCE(v.UpVoteCount,   0) * 1.5
         - COALESCE(v.DownVoteCount, 0) * 2)       AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentQuestionRank
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount
        FROM Comments
        WHERE LOWER(Text) LIKE '%error%' OR LOWER(Text) LIKE '%bug%'
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1                         -- questions only
),

DuplicateChains AS (
    SELECT
        p.Id,
        pl.RelatedPostId      AS DuplicateOf,
        pl.CreationDate       AS DuplicateMarkDate,
        LAG(pl.RelatedPostId) OVER (PARTITION BY p.Id ORDER BY pl.CreationDate) AS PrevDuplicate
    FROM Posts p
    JOIN PostLinks pl
        ON pl.PostId = p.Id
       AND pl.LinkTypeId = 3                      -- Duplicate links
),

Combined AS (
    SELECT
        pe.Id,
        pe.Title,
        pe.CreationDate,
        pe.EngagementScore,
        um.Reputation,
        um.GoldBadges,
        um.SilverBadges,
        um.BronzeBadges,
        um.ReputationRank,
        ts.TagName,
        dc.DuplicateOf
    FROM PostEngagement pe
    LEFT JOIN UserMetrics um
        ON um.UserId = pe.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(pe.Tags, 2, length(pe.Tags)-2), '><')) AS TagName
    ) t ON true
    LEFT JOIN TagStats ts
        ON ts.TagName = t.TagName
    LEFT JOIN DuplicateChains dc
        ON dc.Id = pe.Id
)

SELECT *
FROM Combined
WHERE EngagementScore > 500
  AND (GoldBadges > 0 OR ReputationRank <= 100)
  AND TagName IS NOT NULL
ORDER BY EngagementScore DESC, CreationDate DESC
LIMIT 100 OFFSET 0;
