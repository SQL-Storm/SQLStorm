WITH RECURSIVE RecursiveUserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        1 AS BadgeCount,
        b.Id AS BadgeId
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId

    UNION ALL

    SELECT
        rub.UserId,
        rub.DisplayName,
        rub.Reputation,
        b2.Class,
        rub.BadgeCount + 1,
        b2.Id
    FROM RecursiveUserBadges rub
    JOIN Badges b2 ON rub.UserId = b2.UserId
    WHERE b2.Id > (SELECT max(Id) FROM Badges WHERE UserId = rub.UserId)
        AND rub.BadgeCount < 3
),
TopPostsWithRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        row_number() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS RankWithinType,
        dense_rank() OVER (ORDER BY p.CreationDate DESC) AS RecencyRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
CteCombined AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id AS OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.Views AS UserViews,
        u.UpVotes,
        u.DownVotes,
        pb1.BadgeCounts_Gold,
        pb1.BadgeCounts_Silver,
        pb1.BadgeCounts_Bronze,
        p.Title,
        p.Tags,
        ph_latest.Text AS LatestEditComment,
        c.NumComments,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        xp.LinkCount_Duplicate,
        xp.LinkCount_Linked
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS BadgeCounts_Gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS BadgeCounts_Silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BadgeCounts_Bronze
        FROM Badges b
        GROUP BY b.UserId
    ) pb1 ON u.Id = pb1.UserId
    LEFT JOIN (
        SELECT ph.PostId, max(ph.Id) AS MaxPHId
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4,5)
        GROUP BY ph.PostId
    ) phmax ON phmax.PostId = p.Id
    LEFT JOIN PostHistory ph_latest ON ph_latest.Id = phmax.MaxPHId
    LEFT JOIN (
        SELECT PostId, count(*) AS NumComments
        FROM Comments
        GROUP BY PostId
    ) c ON p.Id = c.PostId
    LEFT JOIN (
        SELECT
            pl.PostId,
            SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS LinkCount_Duplicate,
            SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkCount_Linked
        FROM PostLinks pl
        GROUP BY pl.PostId
    ) xp ON xp.PostId = p.Id
    WHERE p.PostTypeId = 1
),
RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
HighScoreComments AS (
    SELECT
        c.PostId,
        string_agg(c.Text, ' ||| ' ORDER BY c.Score DESC, c.CreationDate ASC) AS TopComments
    FROM Comments c
    WHERE c.Score > (SELECT avg(Score) FROM Comments WHERE Score IS NOT NULL)
    GROUP BY c.PostId
),
UserLastActive AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.LastAccessDate,
        dense_rank() OVER (ORDER BY u.LastAccessDate DESC) AS RecentAccessRank
    FROM Users u
)
SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.Score AS QuestionScore,
    c.ViewCount,
    c.CreationDate,
    c.DisplayName AS QuestionOwnerName,
    c.Reputation AS QuestionOwnerReputation,
    c.BadgeCounts_Gold,
    c.BadgeCounts_Silver,
    c.BadgeCounts_Bronze,
    c.HasAcceptedAnswer,
    c.NumComments AS QuestionCommentCount,
    coalesce(rq_highest.Score, 0) AS TopAnswerScore,
    coalesce(rq_highest.AnswerOwnerName, 'N/A') AS TopAnswerOwner,
    coalesce(rq_highest.AnswerOwnerReputation, 0) AS TopAnswerOwnerReputation,
    c.LatestEditComment,
    ua.LastAccessDate AS QuestionOwnerLastAccess,
    csrf.TagsAreClean,
    hc.TopComments,
    fold.LinkedDuplicatesRatio,
    fold.LinkedDuplicatesScore
FROM CteCombined c
LEFT JOIN LATERAL (
    SELECT
        a.Score,
        u.DisplayName AS AnswerOwnerName,
        u.Reputation AS AnswerOwnerReputation,
        a.CreationDate
    FROM RankedAnswers a
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.QuestionId = c.PostId AND a.AnswerRank = 1
    ORDER BY a.Score DESC, a.CreationDate ASC
    LIMIT 1
) rq_highest ON TRUE
LEFT JOIN UserLastActive ua ON ua.Id = c.OwnerUserId
LEFT JOIN HighScoreComments hc ON hc.PostId = c.PostId
LEFT JOIN LATERAL (
    SELECT
        CASE
            WHEN (coalesce(c.LinkCount_Duplicate,0) + coalesce(c.LinkCount_Linked,0)) = 0 THEN 0.0
            ELSE (CAST(coalesce(c.LinkCount_Duplicate,0) AS double precision) / GREATEST(coalesce(c.LinkCount_Duplicate,0) + coalesce(c.LinkCount_Linked,0),1))
        END AS LinkedDuplicatesRatio,
        coalesce(c.LinkCount_Duplicate,0) * coalesce(c.ViewCount,0) AS LinkedDuplicatesScore
) fold ON TRUE
LEFT JOIN LATERAL (
    SELECT
        CASE WHEN position('<sql>' IN coalesce(c.Tags,'')) > 0 OR position('query' IN coalesce(c.Title,'')) > 0 THEN false ELSE true END AS TagsAreClean
) csrf ON TRUE
WHERE c.Score >= ALL (
    SELECT p3.score - 5 FROM Posts p3
    WHERE p3.PostTypeId = 1 AND p3.AcceptedAnswerId IS NOT NULL
)
GROUP BY
    c.PostId,
    c.Title,
    c.Tags,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.DisplayName,
    c.Reputation,
    c.BadgeCounts_Gold,
    c.BadgeCounts_Silver,
    c.BadgeCounts_Bronze,
    c.HasAcceptedAnswer,
    c.NumComments,
    c.LatestEditComment,
    ua.LastAccessDate,
    csrf.TagsAreClean,
    hc.TopComments,
    fold.LinkedDuplicatesRatio,
    fold.LinkedDuplicatesScore,
    rq_highest.Score,
    rq_highest.AnswerOwnerName,
    rq_highest.AnswerOwnerReputation
ORDER BY c.Score DESC, TopAnswerScore DESC, c.ViewCount DESC
LIMIT 50;