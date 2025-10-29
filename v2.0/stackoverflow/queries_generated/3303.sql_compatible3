WITH
    q AS (
        SELECT
            p.Id                         AS QuestionId,
            p.Title,
            p.OwnerUserId,
            p.CreationDate,
            p.Score                      AS QuestionScore,
            p.Tags,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
            p.ClosedDate,
            p.CommunityOwnedDate
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    top_questions AS (
        SELECT *
        FROM q
        WHERE rn <= 5
    ),
    answer_stats AS (
        SELECT
            a.ParentId                                   AS QuestionId,
            SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END)                                   AS PositiveAnswers,
            SUM(CASE WHEN a.Score <= 0 THEN 1 ELSE 0 END)                                  AS NonPositiveAnswers,
            MAX(a.Score)                                 AS MaxAnswerScore,
            CAST(AVG(a.Score) AS DECIMAL(10,2))          AS AvgAnswerScore
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ),
    user_badges AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)          AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)          AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)          AS BronzeBadges,
            STRING_AGG(DISTINCT b.Name, ', ')            AS BadgeList
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_votes AS (
        SELECT
            v.PostId,
            SUM(CASE
                    WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1
                    ELSE 0
                END)                                      AS NetScore,
            MAX(v.CreationDate)                          AS LastVoteDate
        FROM Votes v
        WHERE v.VoteTypeId IN (2,3)
        GROUP BY v.PostId
    )
SELECT
    tq.QuestionId,
    tq.Title,
    COALESCE(u.DisplayName, 'Anonymous')                AS OwnerDisplayName,
    tq.QuestionScore,
    tq.Tags,
    COALESCE(ab.PositiveAnswers,0)                      AS PositiveAnswers,
    COALESCE(ab.NonPositiveAnswers,0)                   AS NonPositiveAnswers,
    ab.MaxAnswerScore,
    ab.AvgAnswerScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.BadgeList,
    rv.NetScore                                         AS QuestionNetVoteScore,
    rv.LastVoteDate,
    (SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
          AND pl.RelatedPostId = tq.QuestionId)          AS DuplicateLinkCount,
    RANK() OVER (ORDER BY
                 (tq.QuestionScore
                  + COALESCE(rv.NetScore,0)
                  + COALESCE(ab.AvgAnswerScore,0)) DESC) AS ActivityRank,
    COALESCE(
        CASE
            WHEN tq.Tags IS NULL THEN NULL
            WHEN POSITION('><' IN tq.Tags) > 0 THEN SUBSTRING(tq.Tags FROM 2 FOR POSITION('><' IN tq.Tags) - 2)
            ELSE
                CASE
                    WHEN LEFT(tq.Tags,1) = '<' AND RIGHT(tq.Tags,1) = '>' THEN SUBSTRING(tq.Tags FROM 2 FOR CHAR_LENGTH(tq.Tags) - 2)
                    WHEN LEFT(tq.Tags,1) = '<' THEN SUBSTRING(tq.Tags FROM 2)
                    WHEN RIGHT(tq.Tags,1) = '>' THEN SUBSTRING(tq.Tags FROM 1 FOR CHAR_LENGTH(tq.Tags) - 1)
                    ELSE tq.Tags
                END
        END,
        'no-tag')                                        AS PrimaryTag,
    CASE
        WHEN tq.ClosedDate IS NOT NULL          THEN 'Closed'
        WHEN tq.CommunityOwnedDate IS NOT NULL  THEN 'Community Owned'
        ELSE 'Open'
    END                                                AS Status
FROM top_questions tq
LEFT JOIN Users u         ON u.Id = tq.OwnerUserId
LEFT JOIN answer_stats ab ON ab.QuestionId = tq.QuestionId
LEFT JOIN user_badges ub  ON ub.UserId = tq.OwnerUserId
LEFT JOIN recent_votes rv ON rv.PostId = tq.QuestionId

UNION ALL

SELECT
    p.Id                                                   AS QuestionId,
    p.Title,
    COALESCE(u.DisplayName, 'Anonymous')                    AS OwnerDisplayName,
    p.Score                                                 AS QuestionScore,
    p.Tags,
    0                                                       AS PositiveAnswers,
    0                                                       AS NonPositiveAnswers,
    NULL                                                    AS MaxAnswerScore,
    NULL                                                    AS AvgAnswerScore,
    NULL                                                    AS GoldBadges,
    NULL                                                    AS SilverBadges,
    NULL                                                    AS BronzeBadges,
    NULL                                                    AS BadgeList,
    NULL                                                    AS QuestionNetVoteScore,
    NULL                                                    AS LastVoteDate,
    0                                                       AS DuplicateLinkCount,
    NULL                                                    AS ActivityRank,
    COALESCE(
        CASE
            WHEN p.Tags IS NULL THEN NULL
            WHEN POSITION('><' IN p.Tags) > 0 THEN SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2)
            ELSE
                CASE
                    WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
                    WHEN LEFT(p.Tags,1) = '<' THEN SUBSTRING(p.Tags FROM 2)
                    WHEN RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 1 FOR CHAR_LENGTH(p.Tags) - 1)
                    ELSE p.Tags
                END
        END,
        'no-tag')                                            AS PrimaryTag,
    CASE
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Other'
    END                                                     AS Status
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId IN (4,5)
  AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)

ORDER BY ActivityRank ASC NULLS LAST, QuestionId;