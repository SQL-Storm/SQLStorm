-- {"query": "24031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3717} 
WITH UserSummary AS (
    SELECT
        u.Id          AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 END),0)   AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 END),0)   AS AnswerCount,
        COALESCE(SUM(p.ViewCount),0)                            AS TotalViews,
        COALESCE(MAX(p.LastActivityDate),u.CreationDate)        AS LatestPostDate,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 END),0)       AS GoldBadgeCnt,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 END),0)       AS SilverBadgeCnt,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 END),0)       AS BronzeBadgeCnt,
        COALESCE(COUNT(DISTINCT t.TagName),0)                   AS DistinctTagCnt
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Tags t ON (p.Tags LIKE CONCAT('%', t.TagName, '%') AND p.PostTypeId = 1)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionStats AS (
    SELECT
        p.Id            AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        COALESCE((
            SELECT AVG(vr.Reputation)
            FROM Votes v
            JOIN Users vr ON vr.Id = v.UserId
            WHERE v.VoteTypeId = 2
              AND v.PostId = p.AcceptedAnswerId
        ),0) AS AvgUpvoteReputationOfAccepted,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS QRankByScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagAggregate AS (
    SELECT
        q.OwnerUserId,
        t.TagName,
        COUNT(*) AS TagAppearances
    FROM QuestionStats q
    JOIN Tags t ON q.Tags LIKE CONCAT('%', t.TagName, '%')
    GROUP BY q.OwnerUserId, t.TagName

    UNION ALL

    SELECT
        q.OwnerUserId,
        NULL AS TagName,
        COUNT(*) AS TagAppearances
    FROM QuestionStats q
    WHERE q.Tags IS NULL
    GROUP BY q.OwnerUserId
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalViews,
    us.LatestPostDate,
    us.GoldBadgeCnt,
    us.SilverBadgeCnt,
    us.BronzeBadgeCnt,
    us.DistinctTagCnt,
    qs.QuestionId,
    qs.Title,
    qs.Score,
    qs.ViewCount,
    qs.AvgUpvoteReputationOfAccepted,
    qs.QRankByScore,
    CASE
        WHEN qs.AvgUpvoteReputationOfAccepted > 100 THEN 'Highly Upvoted'
        WHEN qs.Score >= 10 THEN 'Hot'
        ELSE 'Regular'
    END AS QuestionStatus,
    tagg.TagName,
    tagg.TagAppearances
FROM UserSummary us
LEFT JOIN QuestionStats qs ON qs.OwnerUserId = us.UserId
LEFT JOIN TagAggregate tagg ON tagg.OwnerUserId = us.UserId
ORDER BY us.QuestionCount DESC, qs.Score DESC, tagg.TagAppearances DESC;