WITH
    TagList AS (
        SELECT t.Id   AS TagId,
               t.TagName
        FROM   Tags t
        WHERE  t.IsModeratorOnly = FALSE
    ),
    QuestionPosts AS (
        SELECT p.Id,
               p.Tags,
               p.OwnerUserId,
               p.Score,
               p.CreationDate
        FROM   Posts p
        WHERE  p.PostTypeId = 1
    ),
    AnswerPosts AS (
        SELECT a.Id,
               a.ParentId,
               a.OwnerUserId,
               a.Score,
               a.CreationDate,
               q.Tags
        FROM   Posts a
        JOIN   QuestionPosts q ON a.ParentId = q.Id
        WHERE  a.PostTypeId = 2
    ),
    AnswerVoteCounts AS (
        SELECT v.PostId,
               COUNT(*) AS UpVoteCnt
        FROM   Votes v
        WHERE  v.VoteTypeId = 2
        GROUP BY v.PostId
    ),
    UserBadgeClass AS (
        SELECT b.UserId,
               MAX(b.Class) AS HighestClass
        FROM   Badges b
        GROUP BY b.UserId
    ),
    UserStatsPerTag AS (
        SELECT
            t.TagName,
            u.Id                         AS UserId,
            COALESCE(u.DisplayName, 'Deleted') AS DisplayName,
            u.Reputation,
            COUNT(*)                     AS AnswerCnt,
            COUNT(CASE WHEN a.Score > 0 THEN 1 END)  AS PositiveAnswers,
            COUNT(CASE WHEN a.Score <= 0 THEN 1 END) AS NonPositiveAnswers,
            ROUND(AVG(CAST(a.Score AS NUMERIC)), 2)      AS AvgScore,
            SUM(COALESCE(v.UpVoteCnt,0))          AS TotalUpVotes,
            COALESCE(b.HighestClass, 3)           AS HighestBadgeClass
        FROM   TagList t
        JOIN   AnswerPosts a
               ON a.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
        JOIN   Users u ON u.Id = a.OwnerUserId
        LEFT JOIN AnswerVoteCounts v ON v.PostId = a.Id
        LEFT JOIN UserBadgeClass b   ON b.UserId = u.Id
        GROUP BY t.TagName, u.Id, u.DisplayName, u.Reputation, b.HighestClass
    ),
    RankedUserStats AS (
        SELECT TagName,
               UserId,
               DisplayName,
               Reputation,
               AnswerCnt,
               PositiveAnswers,
               NonPositiveAnswers,
               AvgScore,
               TotalUpVotes,
               HighestBadgeClass,
               ROW_NUMBER() OVER (PARTITION BY TagName
                                  ORDER BY Reputation DESC, AvgScore DESC) AS rn
        FROM   UserStatsPerTag
    )
SELECT
    TagName,
    UserId,
    DisplayName,
    Reputation,
    AnswerCnt,
    PositiveAnswers,
    NonPositiveAnswers,
    AvgScore,
    TotalUpVotes,
    HighestBadgeClass
FROM   RankedUserStats
WHERE  rn <= 5

UNION ALL

SELECT
    'Overall'                                    AS TagName,
    u.Id,
    COALESCE(u.DisplayName, 'Deleted')           AS DisplayName,
    u.Reputation,
    COUNT(a.Id)                                  AS AnswerCnt,
    COUNT(CASE WHEN a.Score > 0 THEN 1 END)       AS PositiveAnswers,
    COUNT(CASE WHEN a.Score <= 0 THEN 1 END)      AS NonPositiveAnswers,
    ROUND(AVG(CAST(a.Score AS NUMERIC)), 2)              AS AvgScore,
    SUM(COALESCE(v.UpVoteCnt,0))                 AS TotalUpVotes,
    COALESCE(b.HighestClass, 3)                  AS HighestBadgeClass
FROM   Users u
LEFT JOIN AnswerPosts a      ON a.OwnerUserId = u.Id
LEFT JOIN AnswerVoteCounts v ON v.PostId = a.Id
LEFT JOIN UserBadgeClass b    ON b.UserId = u.Id
GROUP BY u.Id, u.DisplayName, u.Reputation, b.HighestClass
ORDER BY TagName, Reputation DESC, AvgScore DESC;