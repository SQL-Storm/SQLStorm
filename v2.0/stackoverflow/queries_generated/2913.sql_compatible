WITH RecursiveTags AS (
    SELECT
        p.Id AS PostId,
        TRIM(regexp_split_to_table(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
PostWithTagRank AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        t.Tag,
        RANK() OVER (PARTITION BY p.Id ORDER BY length(t.Tag) DESC, t.Tag) AS TagLengthRank
    FROM Posts p
    LEFT JOIN RecursiveTags t ON p.Id = t.PostId
    WHERE p.PostTypeId = 1
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
ClosedQuestionDetails AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS ClosedAt,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS ReopenedAt,
        cr.Name AS CloseReason
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON ph.Comment = CAST(cr.Id AS varchar) AND ph.PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId IN (10,11)
    GROUP BY ph.PostId, cr.Name
),
AnswerStats AS (
    SELECT
        p.ParentId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
WindowedUserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationReputationRank,
        COUNT(*) OVER (PARTITION BY u.Location) AS UsersInLocation
    FROM Users u
    WHERE u.Location IS NOT NULL AND LENGTH(u.Location) > 0
),
DistinctDuplicateLinks AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
TaggedQuestionsWithStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        pwtr.Tag,
        pwtr.TagLengthRank,
        uc.GoldBadges,
        uc.SilverBadges,
        uc.BronzeBadges,
        cd.ClosedAt,
        cd.ReopenedAt,
        cd.CloseReason,
        COALESCE(ans.AnswerCount, 0) AS AnswerCount,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(ans.TotalUpVotes, 0) AS TotalUpVotes,
        COALESCE(ans.TotalDownVotes, 0) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN PostWithTagRank pwtr ON pwtr.Id = p.Id AND pwtr.TagLengthRank = 1
    LEFT JOIN UserBadgeCounts uc ON uc.UserId = p.OwnerUserId
    LEFT JOIN ClosedQuestionDetails cd ON cd.PostId = p.Id
    LEFT JOIN AnswerStats ans ON ans.ParentId = p.Id
    WHERE p.PostTypeId = 1
)
SELECT
    tqws.QuestionId,
    tqws.Title,
    COALESCE(u.DisplayName, CAST(tqws.OwnerUserId AS varchar) || ' (deleted)') AS QuestionOwner,
    tqws.Score,
    tqws.ViewCount,
    tqws.CreationDate,
    tqws.Tag,
    ('G:' || COALESCE(tqws.GoldBadges, 0) || ', S:' || COALESCE(tqws.SilverBadges, 0) || ', B:' || COALESCE(tqws.BronzeBadges, 0)) AS OwnerBadgeSummary,
    CASE
        WHEN tqws.ClosedAt IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    COALESCE(tqws.CloseReason, 'N/A') AS CloseReason,
    tqws.AnswerCount,
    ROUND(CAST(tqws.AvgAnswerScore AS numeric), 2) AS AvgAnswerScore,
    tqws.MaxAnswerScore,
    tqws.TotalUpVotes,
    tqws.TotalDownVotes,
    wu.Location,
    wu.LocationReputationRank,
    wu.UsersInLocation,
    CASE 
        WHEN wl.PostId IS NOT NULL THEN 'Yes' 
        ELSE 'No' 
    END AS IsMarkedDuplicate,
    LEFT(tqws.Title, 50) || CASE WHEN LENGTH(tqws.Title) > 50 THEN '...' ELSE '' END AS ShortTitle,
    (SELECT LENGTH(c.Text) FROM Comments c WHERE c.PostId = tqws.QuestionId ORDER BY c.CreationDate DESC LIMIT 1) AS LatestCommentTextLength,
    CASE WHEN u.DisplayName IS NOT NULL THEN reverse(u.DisplayName) ELSE NULL END AS ReversedOwnerDisplayName
FROM TaggedQuestionsWithStats tqws
LEFT JOIN Users u ON u.Id = tqws.OwnerUserId
LEFT JOIN WindowedUserReputation wu ON wu.Id = tqws.OwnerUserId
LEFT JOIN DistinctDuplicateLinks wl ON wl.PostId = tqws.QuestionId
WHERE
    (
        (tqws.AnswerCount > 10 AND tqws.Score > 5)
        OR (tqws.ClosedAt IS NOT NULL AND tqws.CloseReason IS NOT NULL)
    )
    AND (
        (wu.Location IS NOT NULL AND wu.LocationReputationRank <= 3)
        OR wu.Location IS NULL
    )
UNION ALL
SELECT
    a.Id AS QuestionId,
    a.Title,
    COALESCE(u.DisplayName, CAST(a.OwnerUserId AS varchar) || ' (deleted)') AS QuestionOwner,
    a.Score,
    a.ViewCount,
    a.CreationDate,
    'N/A' AS Tag,
    '0,0,0' AS OwnerBadgeSummary,
    'Open' AS QuestionStatus,
    'N/A' AS CloseReason,
    0 AS AnswerCount,
    0.0 AS AvgAnswerScore,
    0 AS MaxAnswerScore,
    0 AS TotalUpVotes,
    0 AS TotalDownVotes,
    NULL AS Location,
    NULL AS LocationReputationRank,
    NULL AS UsersInLocation,
    'No' AS IsMarkedDuplicate,
    LEFT(a.Title, 50) || CASE WHEN LENGTH(a.Title) > 50 THEN '...' ELSE '' END AS ShortTitle,
    NULL AS LatestCommentTextLength,
    CASE WHEN u.DisplayName IS NOT NULL THEN reverse(u.DisplayName) ELSE NULL END AS ReversedOwnerDisplayName
FROM Posts a
LEFT JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN Posts q ON a.ParentId = q.Id AND q.AcceptedAnswerId IS NULL
WHERE a.PostTypeId = 2
  AND a.Score > 20
  AND q.Id IS NOT NULL
ORDER BY AnswerCount DESC, Score DESC, CreationDate DESC
LIMIT 150;