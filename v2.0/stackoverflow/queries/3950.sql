-- {"query": "3950.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2582}
WITH TopTags AS (
    SELECT 
        TagName,
        Count,
        ROW_NUMBER() OVER (ORDER BY Count DESC) AS rn
    FROM Tags
    WHERE IsModeratorOnly = FALSE 
      AND IsRequired = FALSE
),
QuestionStats AS (
    SELECT 
        p.Id                         AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score                      AS QuestionScore,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        p.ClosedDate,
        u.Id                         AS OwnerUserId,
        COALESCE(u.Reputation,0)     AS OwnerReputation,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.ParentId = p.Id 
           AND a.PostTypeId = 2)    AS AnswerCount,
        (SELECT AVG(a.Score) 
         FROM Posts a 
         WHERE a.ParentId = p.Id 
           AND a.PostTypeId = 2)    AS AvgAnswerScore,
        (SELECT MAX(v.CreationDate) 
         FROM Votes v 
         WHERE v.PostId = p.Id 
           AND v.VoteTypeId = 2)    AS LastUpvoteDate
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2020-01-01'
),
TagExplode AS (
    SELECT 
        q.QuestionId,
        TRIM(BOTH '><' FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(q.Tags,2,LENGTH(q.Tags)-2), '><'))) AS Tag
    FROM QuestionStats q
),
TagMetrics AS (
    SELECT 
        te.QuestionId,
        te.Tag,
        t.Count                         AS TagGlobalCount,
        ROW_NUMBER() OVER (PARTITION BY te.QuestionId ORDER BY t.Count DESC) AS TagRank
    FROM TagExplode te
    LEFT JOIN Tags t ON t.TagName = te.Tag
),
UserBadgeCounts AS (
    SELECT 
        UserId,
        COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
),
RankedQuestions AS (
    SELECT 
        qs.QuestionId,
        qs.Title,
        qs.CreationDate,
        qs.QuestionScore,
        qs.ViewCount,
        qs.FavoriteCount,
        qs.Tags,
        qs.ClosedDate,
        qs.OwnerUserId,
        qs.OwnerReputation,
        qs.AnswerCount,
        qs.AvgAnswerScore,
        qs.LastUpvoteDate,
        ROW_NUMBER() OVER (PARTITION BY qs.OwnerUserId ORDER BY qs.QuestionScore DESC, qs.CreationDate) AS UserQuestionRank,
        COALESCE(ubc.BadgeCount,0)       AS OwnerBadgeCount,
        CASE WHEN qs.ClosedDate IS NOT NULL THEN 1 ELSE 0 END                  AS IsClosed,
        (SELECT STRING_AGG(DISTINCT CAST(v.VoteTypeId AS VARCHAR), ',')
         FROM Votes v
         WHERE v.PostId = qs.QuestionId) AS VoteTypesSeen
    FROM QuestionStats qs
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = qs.OwnerUserId
),
FinalQuestions AS (
    SELECT 
        rq.QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.OwnerReputation,
        rq.QuestionScore,
        rq.ViewCount,
        rq.FavoriteCount,
        rq.AnswerCount,
        ROUND(rq.AvgAnswerScore,2)      AS AvgAnswerScore,
        rq.LastUpvoteDate,
        rq.UserQuestionRank,
        rq.OwnerBadgeCount,
        rq.IsClosed,
        rq.VoteTypesSeen,
        tm.Tag,
        tm.TagGlobalCount,
        tm.TagRank
    FROM RankedQuestions rq
    LEFT JOIN TagMetrics tm 
        ON tm.QuestionId = rq.QuestionId 
       AND tm.TagRank <= 3
    WHERE rq.UserQuestionRank <= 5
),
TopAnswers AS (
    SELECT 
        a.Id                               AS AnswerId,
        a.ParentId                         AS QuestionId,
        a.Score                            AS AnswerScore,
        a.CreationDate,
        a.OwnerUserId,
        COALESCE(u.Reputation,0)           AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= DATE '2020-01-01'
),
TopAnswersFiltered AS (
    SELECT *
    FROM TopAnswers
    WHERE AnswerRank <= 3
),
Combined AS (
    SELECT 
        fq.QuestionId,
        fq.Title,
        fq.OwnerUserId,
        fq.OwnerReputation,
        fq.QuestionScore,
        fq.ViewCount,
        fq.FavoriteCount,
        fq.AnswerCount,
        fq.AvgAnswerScore,
        fq.LastUpvoteDate,
        fq.UserQuestionRank,
        fq.OwnerBadgeCount,
        fq.IsClosed,
        fq.VoteTypesSeen,
        fq.Tag,
        fq.TagGlobalCount,
        fq.TagRank,
        CAST(NULL AS INTEGER)        AS AnswerId,
        CAST(NULL AS INTEGER)        AS AnswerScore,
        CAST(NULL AS TIMESTAMP)  AS AnswerCreationDate,
        CAST(NULL AS INTEGER)        AS AnswerOwnerUserId,
        CAST(NULL AS INTEGER)        AS AnswerOwnerReputation,
        CAST(NULL AS INTEGER)        AS AnswerRank
    FROM FinalQuestions fq
    WHERE (fq.OwnerReputation > 1000 OR fq.OwnerBadgeCount >= 5)
      AND (fq.QuestionScore + COALESCE(fq.AvgAnswerScore,0) * 2) > 50
      AND (fq.TagGlobalCount IS NULL OR fq.TagGlobalCount > 5000)

    UNION ALL

    SELECT 
        CAST(NULL AS INTEGER)        AS QuestionId,
        CAST(NULL AS VARCHAR)    AS Title,
        CAST(NULL AS INTEGER)        AS OwnerUserId,
        CAST(NULL AS INTEGER)        AS OwnerReputation,
        CAST(NULL AS INTEGER)        AS QuestionScore,
        CAST(NULL AS INTEGER)        AS ViewCount,
        CAST(NULL AS INTEGER)        AS FavoriteCount,
        CAST(NULL AS INTEGER)        AS AnswerCount,
        CAST(NULL AS NUMERIC)    AS AvgAnswerScore,
        CAST(NULL AS TIMESTAMP)  AS LastUpvoteDate,
        CAST(NULL AS INTEGER)        AS UserQuestionRank,
        CAST(NULL AS INTEGER)        AS OwnerBadgeCount,
        CAST(NULL AS INTEGER)        AS IsClosed,
        CAST(NULL AS VARCHAR)    AS VoteTypesSeen,
        CAST(NULL AS VARCHAR)    AS Tag,
        CAST(NULL AS INTEGER)        AS TagGlobalCount,
        CAST(NULL AS INTEGER)        AS TagRank,
        ta.AnswerId,
        ta.AnswerScore,
        ta.CreationDate   AS AnswerCreationDate,
        ta.OwnerUserId    AS AnswerOwnerUserId,
        ta.OwnerReputation AS AnswerOwnerReputation,
        ta.AnswerRank
    FROM TopAnswersFiltered ta
)
SELECT *
FROM Combined
ORDER BY 
    COALESCE(OwnerReputation,0) DESC,
    COALESCE(QuestionScore,0) DESC,
    COALESCE(AnswerScore,0) DESC
LIMIT 200;