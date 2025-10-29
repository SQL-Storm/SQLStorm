-- {"query": "3049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1852}
WITH
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COALESCE(q.FavoriteCount, 0) AS FavoriteCnt,
        COALESCE(q.AnswerCount, 0) AS AnswerCnt,
        q.Tags,
        CASE
            WHEN q.Tags IS NOT NULL
            THEN split_part(substring(q.Tags FROM 2 FOR char_length(q.Tags) - 2), '><', 1)
            ELSE NULL
        END AS FirstTag,
        (q.Score * 10 + COALESCE(q.ViewCount, 0) / 1000.0) AS PopularityScore
    FROM Posts q
    WHERE q.PostTypeId = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserSince,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS BronzeBadges,
        COALESCE((
            SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE p.OwnerUserId = u.Id
        ), 0) AS NetVoteScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
),
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.LastActivityDate) AS LastActivity,
        STRING_AGG(DISTINCT CONCAT('Q', p.Id), ',') AS SampleQuestionIds
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
                 AND p.PostTypeId = 1
    GROUP BY t.TagName
),
RecentCloses AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        ph.UserId,
        CAST(ph.Comment AS INTEGER) AS CloseReasonId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
),
QA_Union AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        NULL AS ParentId,
        NULL AS AcceptedAnswerId
    FROM Posts p
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT
        a.Id,
        a.PostTypeId,
        NULL AS Title,
        a.Body,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.ParentId,
        NULL AS AcceptedAnswerId
    FROM Posts a
    WHERE a.PostTypeId = 2
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.CreationDate AS QCreated,
    qs.PopularityScore,
    qs.FirstTag,
    RANK() OVER (PARTITION BY qs.FirstTag ORDER BY qs.PopularityScore DESC) AS TagRank,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.NetVoteScore,
    rc.CloseReasonId,
    rc.CreationDate AS CloseDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qs.QuestionId) AS CommentCount,
    (SELECT COUNT(*) FROM QA_Union qau WHERE qau.Id = qs.QuestionId OR qau.ParentId = qs.QuestionId) AS TotalRelatedPosts,
    tm.QuestionCount AS TagQuestionCount,
    tm.AvgScore AS TagAvgScore,
    tm.LastActivity AS TagLastActivity,
    tm.SampleQuestionIds
FROM QuestionStats qs
LEFT JOIN UserActivity ua
       ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = qs.QuestionId)
LEFT JOIN RecentCloses rc
       ON rc.PostId = qs.QuestionId AND rc.rn = 1
LEFT JOIN TagMetrics tm
       ON tm.TagName = qs.FirstTag
WHERE
    (qs.PopularityScore > 50
     OR (qs.FirstTag IS NOT NULL AND LOWER(qs.FirstTag) LIKE '%sql%')
     OR qs.Title IS NULL)
  AND (qs.AnswerCnt = 0 OR qs.FavoriteCnt > 0)
GROUP BY
    qs.QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.PopularityScore,
    qs.FirstTag,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.NetVoteScore,
    rc.CloseReasonId,
    rc.CreationDate,
    tm.QuestionCount,
    tm.AvgScore,
    tm.LastActivity,
    tm.SampleQuestionIds
ORDER BY qs.PopularityScore DESC
LIMIT 100
OFFSET 0;