WITH UserEngagementMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalOwnedPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoriteCount,
        COALESCE(MAX(p.LastActivityDate), CAST('1900-01-01' AS timestamp)) AS LastPostActivity,
        AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionViewCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentMetrics AS (
    SELECT
        c.UserId AS UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(MAX(c.CreationDate), CAST('1900-01-01' AS timestamp)) AS LastCommentActivity
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteSummary AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
        MAX(v.CreationDate) AS LastVoteCastDate
    FROM Votes v
    WHERE v.UserId IS NOT NULL AND v.VoteTypeId IN (2, 3)
    GROUP BY v.UserId
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags <> '' AND p.OwnerUserId IS NOT NULL
),
UserHistorySnapshot AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS HistoryDate,
        LAG(ph.CreationDate, 1, CAST('1970-01-01' AS timestamp)) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        LEAD(ph.CreationDate, 1, CAST('2200-01-01' AS timestamp)) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate) AS NextHistoryDate
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL
),
UsersWithHighEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(uem.TotalOwnedPosts, 0) AS TotalPosts,
        COALESCE(uem.QuestionsAsked, 0) AS QuestionsAsked,
        COALESCE(uem.AnswersProvided, 0) AS AnswersProvided,
        COALESCE(uem.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(uem.AvgQuestionViewCount, 0) AS AvgQuestionViewCount,
        COALESCE(ucm.TotalCommentsMade, 0) AS TotalComments,
        COALESCE(uvs.UpVotesCast, 0) AS UpVotesGiven,
        COALESCE(uvs.DownVotesCast, 0) AS DownVotesGiven,
        'HighRep_Answerer' AS UserSegment
    FROM Users u
    LEFT JOIN UserEngagementMetrics uem ON u.Id = uem.UserId
    LEFT JOIN UserCommentMetrics ucm ON u.Id = ucm.UserId
    LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
    WHERE u.Reputation >= 10000 AND COALESCE(uem.AnswersProvided, 0) >= 50
      AND u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
UsersWithDiverseTags AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(uem.TotalOwnedPosts, 0) AS TotalPosts,
        COALESCE(uem.QuestionsAsked, 0) AS QuestionsAsked,
        COALESCE(uem.AnswersProvided, 0) AS AnswersProvided,
        COALESCE(uem.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(uem.AvgQuestionViewCount, 0) AS AvgQuestionViewCount,
        COALESCE(ucm.TotalCommentsMade, 0) AS TotalComments,
        COALESCE(uvs.UpVotesCast, 0) AS UpVotesGiven,
        COALESCE(uvs.DownVotesCast, 0) AS DownVotesGiven,
        'DiverseTags_Engager' AS UserSegment
    FROM Users u
    LEFT JOIN UserEngagementMetrics uem ON u.Id = uem.UserId
    LEFT JOIN UserCommentMetrics ucm ON u.Id = ucm.UserId
    LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
    INNER JOIN (
        SELECT OwnerUserId, COUNT(DISTINCT TagName) AS UniqueTags, SUM(PostScore) AS TotalTagPostScore
        FROM PostTagAnalysis
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
        HAVING COUNT(DISTINCT TagName) >= 10 AND SUM(PostScore) >= 500
    ) AS TagDiversity ON u.Id = TagDiversity.OwnerUserId
    WHERE u.Reputation >= 1000
),
CombinedUsers AS (
    SELECT * FROM UsersWithHighEngagement
    UNION ALL
    SELECT * FROM UsersWithDiverseTags
)
SELECT
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.UserCreationDate,
    cu.TotalPosts,
    cu.QuestionsAsked,
    cu.AnswersProvided,
    cu.TotalPostScore,
    cu.AvgQuestionViewCount,
    cu.TotalComments,
    cu.UpVotesGiven,
    cu.DownVotesGiven,
    cu.UserSegment,
    RANK() OVER (ORDER BY cu.Reputation DESC, cu.TotalPostScore DESC) AS GlobalReputationRank,
    DENSE_RANK() OVER (PARTITION BY cu.UserSegment ORDER BY cu.Reputation DESC) AS RankInSegment,
    NTILE(5) OVER (ORDER BY cu.Reputation DESC) AS ReputationQuintile,
    (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = cu.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = cu.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = cu.UserId AND b.Class = 3) AS BronzeBadges,
    (cu.UpVotesGiven * 1.0 / NULLIF(cu.DownVotesGiven, 0)) AS GivenVoteRatio,
    COALESCE(
        (SELECT SUM(p_acc.Score)
         FROM Posts p_acc
         WHERE p_acc.AcceptedAnswerId IS NOT NULL
           AND p_acc.AcceptedAnswerId IN (SELECT p_owner.Id FROM Posts p_owner WHERE p_owner.OwnerUserId = cu.UserId AND p_owner.PostTypeId = 2)
        ),
        0
    ) AS ScoreFromAcceptedAnswers,
    (
        SELECT STRING_AGG(sub.TagName, ', ')
        FROM (
            SELECT DISTINCT pta_agg.TagName, pta_agg.PostCreationDate
            FROM PostTagAnalysis pta_agg
            WHERE pta_agg.OwnerUserId = cu.UserId
              AND pta_agg.PostCreationDate >= cu.UserCreationDate
              AND pta_agg.PostScore > (
                  SELECT AVG(p_avg.Score)
                  FROM Posts p_avg
                  WHERE p_avg.PostTypeId = pta_agg.PostTypeId
              )
            ORDER BY pta_agg.TagName
            LIMIT 5
        ) AS sub
    ) AS PreferredTagsWithHighScorePosts,
    COALESCE(
        (SELECT MAX(uhs.HistoryDate) FROM UserHistorySnapshot uhs WHERE uhs.UserId = cu.UserId AND uhs.HistoryTypeName = 'Edit Body'),
        (SELECT MAX(uhs.HistoryDate) FROM UserHistorySnapshot uhs WHERE uhs.UserId = cu.UserId AND uhs.HistoryTypeName = 'Initial Body'),
        cu.UserCreationDate
    ) AS LastContentEditOrCreationDate,
    CASE
        WHEN cu.Reputation > 50000 AND cu.TotalPosts > 500 THEN 'Legendary User'
        WHEN cu.Reputation > 10000 AND cu.TotalPosts > 100 THEN 'Distinguished User'
        WHEN cu.Reputation > 1000 THEN 'Experienced User'
        ELSE 'Contributor'
    END AS DetailedUserTier,
    AGE(
        (SELECT MAX(uhs_max.HistoryDate) FROM UserHistorySnapshot uhs_max WHERE uhs_max.UserId = cu.UserId),
        (SELECT MIN(uhs_min.HistoryDate) FROM UserHistorySnapshot uhs_min WHERE uhs_min.UserId = cu.UserId)
    ) AS TotalUserActivitySpan,
    (
        SELECT STRING_AGG(evt.EventText, '; ')
        FROM (
            SELECT DISTINCT
                CASE
                    WHEN ph_cl.PostHistoryTypeId = 10 AND ph_cl.Comment IS NOT NULL AND crt.Name IS NOT NULL
                    THEN crt.Name
                    WHEN ph_cl.PostHistoryTypeId = 10 AND ph_cl.Comment IS NOT NULL
                    THEN 'Unknown Close Reason (' || ph_cl.Comment || ')'
                    WHEN ph_cl.PostHistoryTypeId = 11 THEN 'Post Reopened'
                    ELSE 'Other Closure/Reopen Event'
                END AS EventText,
                ph_cl.CreationDate
            FROM PostHistory ph_cl
            LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph_cl.Comment AS smallint)
            WHERE ph_cl.PostId IN (SELECT p_q.Id FROM Posts p_q WHERE p_q.OwnerUserId = cu.UserId AND p_q.PostTypeId = 1)
              AND ph_cl.PostHistoryTypeId IN (10, 11)
              AND ph_cl.CreationDate > cu.UserCreationDate - INTERVAL '3 years'
            ORDER BY ph_cl.CreationDate DESC
            LIMIT 1000
        ) AS evt
    ) AS RecentClosureReopenEventsForOwnedQuestions,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId IN (SELECT p_id.Id FROM Posts p_id WHERE p_id.OwnerUserId = cu.UserId AND p_id.PostTypeId = 1)
          AND pl.LinkTypeId = 3
    ) AS TotalDuplicateLinkedQuestions
FROM CombinedUsers cu
WHERE cu.TotalPosts > 0
  AND cu.UserCreationDate BETWEEN CAST('2008-01-01' AS date) AND CAST('2023-12-31' AS date)
ORDER BY cu.Reputation DESC, cu.TotalPostScore DESC
LIMIT 7500;