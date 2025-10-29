-- {"query": "3367.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2522} 
WITH
    QPosts AS (
        SELECT p.Id,
               p.OwnerUserId,
               p.Score,
               p.CreationDate,
               p.Tags
        FROM   Posts p
        WHERE  p.PostTypeId = 1
    ),
    APosts AS (
        SELECT p.Id,
               p.OwnerUserId,
               p.Score,
               p.ParentId,
               p.CreationDate
        FROM   Posts p
        WHERE  p.PostTypeId = 2
    ),
    UserBadgeAgg AS (
        SELECT u.Id                                            AS UserId,
               COUNT(CASE WHEN b.Class = 1 THEN 1 END)         AS GoldBadges,
               COUNT(CASE WHEN b.Class = 2 THEN 1 END)         AS SilverBadges,
               COUNT(CASE WHEN b.Class = 3 THEN 1 END)         AS BronzeBadges,
               COUNT(*)                                        AS TotalBadges
        FROM   Users u
        LEFT  JOIN Badges b ON b.UserId = u.Id
        GROUP  BY u.Id
    ),
    UserTagAgg AS (
        SELECT ub.UserId,
               tg.TagName,
               COUNT(*)                                           AS TagUseCount,
               ROW_NUMBER() OVER (PARTITION BY ub.UserId
                                  ORDER BY COUNT(*) DESC)      AS TagRank
        FROM   (
                 SELECT OwnerUserId AS UserId,
                        UNNEST(string_to_array(trim(both '<>' FROM q.Tags),
                                               '><'))               AS Tag
                 FROM   QPosts q
                 WHERE  q.Tags IS NOT NULL
               ) ub
        JOIN   Tags tg ON tg.TagName = ub.Tag
        GROUP  BY ub.UserId, tg.TagName
    ),
    RecentVote AS (
        SELECT v.UserId,
               MAX(v.CreationDate) AS LastVoteDate
        FROM   Votes v
        WHERE  v.UserId IS NOT NULL
        GROUP  BY v.UserId
    ),
    UserScoreAgg AS (
        SELECT u.Id                                            AS UserId,
               COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END),0) AS QuestionScoreSum,
               COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END),0) AS AnswerScoreSum,
               COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)    AS QuestionCount,
               COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)    AS AnswerCount
        FROM   Users u
        LEFT   JOIN Posts p ON p.OwnerUserId = u.Id
                              AND p.PostTypeId IN (1,2)
        GROUP  BY u.Id
    ),
    TopUserTags AS (
        SELECT UserId,
               TagName,
               TagUseCount
        FROM   UserTagAgg
        WHERE  TagRank = 1
    ),
    UnionSet AS (
        SELECT u.Id        AS UserId,
               'Badge'     AS Source,
               b.TotalBadges AS Value
        FROM   Users u
        JOIN   UserBadgeAgg b ON b.UserId = u.Id

        UNION ALL

        SELECT u.Id,
               'Tag',
               COALESCE(t.TagUseCount,0)
        FROM   Users u
        LEFT   JOIN TopUserTags t ON t.UserId = u.Id
    )
SELECT
    u.Id                                          AS UserId,
    u.DisplayName,
    COALESCE(ub.GoldBadges,0)                     AS GoldBadges,
    COALESCE(ub.SilverBadges,0)                   AS SilverBadges,
    COALESCE(ub.BronzeBadges,0)                   AS BronzeBadges,
    COALESCE(s.QuestionScoreSum,0)                AS TotalQuestionScore,
    COALESCE(s.AnswerScoreSum,0)                  AS TotalAnswerScore,
    COALESCE(s.QuestionCount,0)                   AS TotalQuestions,
    COALESCE(s.AnswerCount,0)                     AS TotalAnswers,
    COALESCE(rv.LastVoteDate,
             TIMESTAMP '1970-01-01')               AS LastVoteTimestamp,
    COALESCE(tut.TagName,'(none)')                AS TopTag,
    COALESCE(tut.TagUseCount,0)                  AS TopTagUseCount,
    (SELECT COUNT(*)
     FROM   Posts p2
     WHERE  p2.OwnerUserId = u.Id
            AND p2.CreationDate > u.CreationDate) AS PostsAfterJoin,
    CONCAT('U',u.Id,'_',REPLACE(COALESCE(u.DisplayName,''),' ','_')) AS UserCode,
    CASE
        WHEN ub.TotalBadges IS NULL THEN 'NoBadges'
        WHEN ub.TotalBadges >= 10   THEN 'PowerUser'
        ELSE 'Regular'
    END                                            AS UserLevel,
    us.Value                                        AS AggregatedMetric
FROM   Users u
LEFT   JOIN UserBadgeAgg ub   ON ub.UserId = u.Id
LEFT   JOIN UserScoreAgg s    ON s.UserId = u.Id
LEFT   JOIN RecentVote rv    ON rv.UserId = u.Id
LEFT   JOIN TopUserTags tut  ON tut.UserId = u.Id
FULL   OUTER JOIN UnionSet us ON us.UserId = u.Id
                               AND us.Source = 'Badge'
WHERE  u.Reputation > 1000
ORDER  BY TotalQuestionScore DESC,
          TotalAnswerScore   DESC
LIMIT  100
OFFSET 0;