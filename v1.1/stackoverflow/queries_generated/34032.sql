-- {"query": "34032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 937} 

WITH RecentQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '6 months'
      AND p.Score > 5
),
TopAnswers AS (
    SELECT 
        a.Id,
        a.ParentId,
        a.CreationDate,
        a.Score,
        a.OwnerUserId,
        u.DisplayName AS AnswererName,
        u.Reputation AS AnswererReputation,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
      AND a.Score >= 3
),
BadgeCounts AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
CommentsStats AS (
    SELECT 
        PostId,
        COUNT(*) AS CommentCount,
        AVG(Score) AS AvgCommentScore,
        MAX(Score) AS MaxCommentScore
    FROM Comments
    WHERE CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY PostId
),
AnswerWithBadges AS (
    SELECT 
        ta.*,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges
    FROM TopAnswers ta
    LEFT JOIN BadgeCounts bc ON ta.OwnerUserId = bc.UserId
    WHERE ta.AnswerRank <= 3
),
LinkedQuestions AS (
    SELECT DISTINCT 
        pl.PostId AS QuestionId,
        pl.RelatedPostId AS LinkedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.PostId IN (SELECT Id FROM RecentQuestions)
      AND lt.Name IN ('Linked', 'Duplicate')
),
TagUsage AS (
    SELECT 
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY Tag
    ORDER BY TagCount DESC
    LIMIT 10
)
SELECT 
    rq.Id AS QuestionId,
    rq.Title,
    rq.CreationDate AS QuestionCreated,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.Tags,
    rq.OwnerName,
    rq.OwnerReputation,
    awb.Id AS AnswerId,
    awb.CreationDate AS AnswerCreated,
    awb.Score AS AnswerScore,
    awb.AnswererName,
    awb.AnswererReputation,
    COALESCE(awb.GoldBadges, 0) AS AnswererGoldBadges,
    COALESCE(awb.SilverBadges, 0) AS AnswererSilverBadges,
    COALESCE(awb.BronzeBadges, 0) AS AnswererBronzeBadges,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.MaxCommentScore,
    lq.LinkedPostId,
    lq.LinkTypeName,
    tu.Tag,
    tu.TagCount
FROM RecentQuestions rq
LEFT JOIN AnswerWithBadges awb ON awb.ParentId = rq.Id
LEFT JOIN CommentsStats cs ON cs.PostId = rq.Id
LEFT JOIN LinkedQuestions lq ON lq.QuestionId = rq.Id
LEFT JOIN TagUsage tu ON POSITION('<' || tu.Tag || '>' IN rq.Tags) > 0
WHERE awb.AnswerRank IS NOT NULL
ORDER BY rq.Score DESC, awb.Score DESC, cs.CommentCount DESC
LIMIT 100;
