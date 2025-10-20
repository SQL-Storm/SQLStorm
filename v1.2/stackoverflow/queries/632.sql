WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.Id
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON NOT (t2.Id = ANY (r.Path)) AND t2.Count < r.Count
    WHERE r.Level < 3
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
PostVotesAgg AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId
),
LatestPostHistoryPerPost AS (
    SELECT ph.PostId,
        ph.Id AS PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment
    FROM (
      SELECT ph.*,
             ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS rn
      FROM PostHistory ph
    ) ph
    WHERE ph.rn = 1
),
UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        -- use RANGE on numeric or use a window over rows; here replace RANGE with a window that counts posts within date range via SUM of condition
        SUM(CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= u.CreationDate - INTERVAL '365 days' AND p.CreationDate <= u.CreationDate THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS QuestionsCountLastYear,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= u.CreationDate - INTERVAL '365 days' AND p.CreationDate <= u.CreationDate THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS AnswersCountLastYear,
        RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
QuestionAnswerPairs AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswerAuthor,
        u.Reputation AS AnswerAuthorReputation,
        pb.UpVotes AS AnswerUpVotes,
        pb.DownVotes AS AnswerDownVotes,
        pb.FavoriteVotes AS AnswerFavoriteVotes,
        pb.TotalBounty AS AnswerBounty
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    LEFT JOIN PostVotesAgg pb ON pb.PostId = a.Id
    WHERE q.PostTypeId = 1 AND q.ClosedDate IS NULL
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE lt.Name = 'Duplicate'
),
ComplexFilteredUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ubc.GoldBadges,0) AS GoldBadges,
        COALESCE(ubc.SilverBadges,0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
        ua.QuestionsCountLastYear,
        ua.AnswersCountLastYear,
        ua.LocationReputationRank,
        COALESCE(pva.UpVotes, 0) AS TotalPostUpVotes,
        COALESCE(pva.DownVotes, 0) AS TotalPostDownVotes
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN UserActivityWindows ua ON ua.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, SUM(UpVotes) AS UpVotes, SUM(DownVotes) AS DownVotes
        FROM PostVotesAgg
        GROUP BY OwnerUserId
    ) pva ON pva.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
      AND (COALESCE(ubc.GoldBadges, 0) > 0 OR COALESCE(ubc.SilverBadges, 0) > 5)
      AND ua.LocationReputationRank <= 10
      AND (COALESCE(ua.QuestionsCountLastYear, 0) + COALESCE(ua.AnswersCountLastYear, 0)) > 20
)
SELECT
    qap.QuestionId,
    qap.Title AS QuestionTitle,
    qap.Tags,
    qap.AnswerId,
    qap.AnswerAuthor,
    qap.AnswerScore,
    qap.AnswerUpVotes,
    qap.AnswerDownVotes,
    qap.AnswerFavoriteVotes,
    qap.AnswerBounty,
    dup.RelatedPostId AS DuplicateOfPostId,
    dup.RelatedPostTitle,
    cfu.Id AS UserId,
    cfu.DisplayName AS UserDisplayName,
    cfu.Reputation AS UserReputation,
    cfu.GoldBadges,
    cfu.SilverBadges,
    cfu.BronzeBadges,
    cfu.QuestionsCountLastYear,
    cfu.AnswersCountLastYear,
    cfu.LocationReputationRank,
    CASE
        WHEN qap.AnswerScore > 10 THEN 'HighScore'
        WHEN qap.AnswerScore BETWEEN 5 AND 10 THEN 'MediumScore'
        ELSE 'LowScore'
    END AS AnswerScoreCategory,
    REGEXP_REPLACE(qap.Tags, '^.*?<([^>]+)>.*$', '\\1') AS FirstTag,
    CHAR_LENGTH(COALESCE(qap.Title, '')) AS TitleLength,
    COALESCE(latestph.PostHistoryTypeId, -1) AS LatestPostHistoryType,
    COALESCE(latestph.Comment, '') AS LatestPostHistoryComment,
    CASE WHEN qap.AnswerFavoriteVotes > 0 THEN TRUE ELSE FALSE END AS HasFavorites,
    CASE
        WHEN COALESCE(cfu.GoldBadges,0) > 0 AND COALESCE(cfu.Reputation,0) > 10000 THEN 'EliteUser'
        WHEN COALESCE(cfu.SilverBadges,0) > 10 THEN 'ExperiencedUser'
        ELSE 'RegularUser'
    END AS UserTier
FROM QuestionAnswerPairs qap
LEFT JOIN DuplicateLinks dup ON dup.PostId = qap.QuestionId
LEFT JOIN ComplexFilteredUsers cfu ON cfu.Id = CASE WHEN qap.AnswerAuthor ~ '^[0-9]+$' THEN CAST(qap.AnswerAuthor AS INTEGER) ELSE NULL END
LEFT JOIN LatestPostHistoryPerPost latestph ON latestph.PostId = qap.QuestionId
WHERE qap.AnswerScore IS NOT NULL
  AND (cfu.Id IS NOT NULL OR qap.AnswerScore > 50)
ORDER BY qap.AnswerScore DESC, cfu.Reputation DESC
LIMIT 100;