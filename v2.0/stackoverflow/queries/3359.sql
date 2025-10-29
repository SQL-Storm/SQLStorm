WITH QuestionStats AS (
    SELECT
        p.Id                                 AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score                              AS QuestionScore,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId,
        COALESCE(u.Reputation, 0)            AS OwnerReputation,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT MAX(v.CreationDate) 
         FROM Votes v 
         WHERE v.PostId = p.Id)                 AS LastVoteDate,
        (SELECT STRING_AGG(DISTINCT t.TagName, ',')
         FROM (
             SELECT UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS tag
         ) tg
         JOIN Tags t ON t.TagName = tg.tag) AS TagList,
        p.AcceptedAnswerId
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
BadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*)                           AS TotalBadges,
        STRING_AGG(DISTINCT b.Name, ';')   AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
RecentCloseReasons AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)   AS CloseReasonId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedOn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name      AS LinkTypeName,
        pl.CreationDate AS LinkCreated
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Id = 3
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
        qs.OwnerUserId,
        qs.OwnerReputation,
        qs.AnswerCount,
        qs.UpVoteCount,
        qs.DownVoteCount,
        qs.LastVoteDate                     AS QSLastVoteDate,
        qs.TagList,
        ROW_NUMBER() OVER (PARTITION BY qs.OwnerUserId 
                           ORDER BY qs.QuestionScore DESC, qs.CreationDate DESC) AS OwnerQuestionRank,
        RANK()        OVER (ORDER BY qs.QuestionScore DESC)                AS GlobalQuestionRank,
        COALESCE(ba.GoldBadges,0)                                         AS OwnerGoldBadges,
        COALESCE(rc.CloseReasonId, NULL)                                  AS CloseReasonId,
        CASE 
            WHEN qs.AnswerCount = 0 THEN 'Unanswered'
            WHEN qs.AnswerCount > 0 AND qs.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
            ELSE 'Answered'
        END                                                               AS AnswerStatus,
        (qs.UpVoteCount - qs.DownVoteCount)                               AS NetVotes,
        COALESCE(rc.ClosedOn, qs.CreationDate)                            AS EffectiveCreation,
        qs.AcceptedAnswerId,
        qs.LastVoteDate
    FROM QuestionStats qs
    LEFT JOIN BadgeAgg ba               ON ba.UserId = qs.OwnerUserId
    LEFT JOIN RecentCloseReasons rc    ON rc.PostId = qs.QuestionId
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.OwnerReputation,
    rq.OwnerGoldBadges,
    rq.GlobalQuestionRank,
    rq.OwnerQuestionRank,
    rq.NetVotes,
    rq.ViewCount,
    rq.FavoriteCount,
    rq.AnswerCount,
    rq.AnswerStatus,
    rq.TagList,
    rq.CloseReasonId,
    COALESCE(dl.RelatedPostId, -1)          AS DuplicateOfQuestionId,
    rq.EffectiveCreation,
    CASE 
        WHEN rq.QSLastVoteDate IS NOT NULL THEN rq.QSLastVoteDate
        ELSE rq.CreationDate
    END                                    AS LastInteractionDate
FROM RankedQuestions rq
LEFT JOIN DuplicateLinks dl ON dl.PostId = rq.QuestionId
WHERE rq.GlobalQuestionRank <= 1000
  AND (rq.OwnerReputation > 1000 OR rq.OwnerGoldBadges > 0)

UNION ALL

SELECT
    a.Id                                   AS QuestionId,
    a.Title,
    a.OwnerUserId,
    u.Reputation,
    0                                      AS OwnerGoldBadges,
    NULL                                   AS GlobalQuestionRank,
    NULL                                   AS OwnerQuestionRank,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = a.Id AND v2.VoteTypeId = 2) -
    (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = a.Id AND v3.VoteTypeId = 3) AS NetVotes,
    a.ViewCount,
    a.FavoriteCount,
    NULL                                   AS AnswerCount,
    'Answer'                               AS AnswerStatus,
    NULL                                   AS TagList,
    NULL                                   AS CloseReasonId,
    NULL                                   AS DuplicateOfQuestionId,
    a.CreationDate,
    a.LastEditDate
FROM Posts a
JOIN Users u ON u.Id = a.OwnerUserId
WHERE a.PostTypeId = 2
  AND a.ParentId IS NOT NULL
  AND a.Score > 10

ORDER BY QuestionId DESC
LIMIT 500;