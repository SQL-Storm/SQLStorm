WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous User') AS DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.Location,
        u.WebsiteUrl,
        u.AboutMe,
        COUNT(DISTINCT b.Name) AS UniqueBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS AccountActiveDays,
        COALESCE(u.WebsiteUrl, 'http://example.com/default') AS CoalescedWebsiteUrl
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 500
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl, u.AboutMe
),
PostAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        AVG(CAST(p.Score AS NUMERIC)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgRelevantPostScorePerPost,
        MAX(p.CreationDate) AS LatestPostDate,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostsCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= DATE '2020-01-01'
    GROUP BY p.OwnerUserId
),
AnswerAcceptance AS (
    SELECT
        p.AcceptedAnswerId AS AnswerId,
        COUNT(DISTINCT p.Id) AS QuestionsAcceptedThisAnswerFor
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
    GROUP BY p.AcceptedAnswerId
),
UserPostTagFrequencies AS (
    -- portable splitter: recursive CTE to split by '><' on tag strings like "<tag1><tag2>"
    SELECT
        OwnerUserId AS UserId,
        LOWER(TRIM(tag)) AS TagName
    FROM (
        SELECT
            p.OwnerUserId,
            CASE WHEN LENGTH(TRIM(p.Tags)) > 2 THEN SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2) ELSE '' END AS inner_tags
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
    ) base
    JOIN LATERAL (
        WITH RECURSIVE splitter(pos, rest) AS (
            SELECT 1 AS pos,
                   base.inner_tags AS rest
            UNION ALL
            SELECT pos + 1,
                   CASE
                     WHEN POSITION('><' IN rest) = 0 THEN ''
                     ELSE SUBSTR(rest, POSITION('><' IN rest) + 2)
                   END
            FROM splitter
            WHERE rest <> ''
              AND (POSITION('><' IN rest) > 0 OR POSITION('><' IN rest) = 0)
        )
        SELECT
            CASE
                WHEN POSITION('><' IN s.rest) = 0 THEN s.rest
                ELSE SUBSTR(s.rest, 1, POSITION('><' IN s.rest) - 1)
            END AS tag
        FROM splitter s
        WHERE s.rest <> ''
    ) split_tags ON 1=1
),
RankedUserTags AS (
    SELECT
        UserId,
        TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC, TagName ASC) AS rn
    FROM UserPostTagFrequencies
    GROUP BY UserId, TagName
),
PostHistoryEditAnalysis AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 ELSE 0 END) AS StatusChangeEvents,
        MAX(ph.CreationDate) AS LastHistoryDate,
        AVG(LENGTH(ph.Text)) FILTER (WHERE ph.PostHistoryTypeId IN (2, 5, 8) AND ph.Text IS NOT NULL) AS AvgBodyContentLengthChange
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId NOT IN (1, 3)
    GROUP BY ph.PostId, ph.UserId
),
OverallAverages AS (
    SELECT
        AVG(u.Reputation) AS AvgReputation,
        AVG(u.Views) AS AvgViews,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScoreOverall,
        AVG(LENGTH(c.Text)) AS AvgCommentLengthOverall
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.AccountActiveDays,
    ue.UniqueBadgeCount,
    ue.GoldBadges,
    pa.TotalPosts,
    pa.QuestionsAsked,
    pa.AnswersProvided,
    pa.TotalPostScore,
    pa.TotalPostViews,
    pa.AvgRelevantPostScorePerPost,
    COALESCE(accepted_ans_owner.TotalAcceptedAnswersContributed, 0) AS AcceptedAnswersContributedByThisUser,
    COALESCE(ph_user_summary.TotalUserEditEvents, 0) AS TotalUserEditEvents,
    ph_user_summary.AvgEditContentLength,
    COALESCE(comm_agg.TotalUserComments, 0) AS TotalUserComments,
    comm_agg.AvgCommentScore,
    tgs.TagName AS TopContributingTag,
    tgs.TagCount AS TopContributingTagCount,
    (SELECT AVG(sub_p.Score) FROM Posts sub_p WHERE sub_p.OwnerUserId = ue.UserId AND sub_p.PostTypeId = 2 AND sub_p.Score IS NOT NULL) AS AverageAnswerScoreByUser,
    oa.AvgReputation AS OverallAvgReputation,
    oa.AvgPostScoreOverall AS OverallAvgPostScore,
    oa.AvgCommentLengthOverall AS OverallAvgCommentLength,
    RANK() OVER (ORDER BY ue.Reputation DESC, COALESCE(pa.TotalPostScore,0) DESC) AS GlobalUserRankByActivity,
    NTILE(10) OVER (ORDER BY (ue.UpVotes - ue.DownVotes) DESC) AS NetVotePowerDecile,
    LAG(ue.Reputation, 1, 0) OVER (ORDER BY ue.CreationDate) AS PreviousUserReputationByCreationOrder,
    (SELECT COUNT(DISTINCT vp.PostId) FROM Votes vp WHERE vp.UserId = ue.UserId AND vp.VoteTypeId = 2) AS UpvotedPostsCountByUser,
    CASE
        WHEN ue.Reputation >= 20000 AND ue.GoldBadges >= 5 AND COALESCE(pa.QuestionsAsked,0) > 20 AND COALESCE(pa.AnswersProvided,0) > 50 THEN 'Super_Guru_Contributor'
        WHEN ue.Reputation >= 10000 AND ue.GoldBadges >= 3 AND COALESCE(pa.AnswersProvided,0) > 20 THEN 'HighRep_Experienced_Responder'
        WHEN ue.Reputation >= 5000 AND COALESCE(pa.QuestionsAsked,0) > 10 THEN 'MidRep_Active_Questioner'
        WHEN ue.Reputation < 2000 AND ue.UniqueBadgeCount > 5 THEN 'Niche_Contributor'
        ELSE 'General_User'
    END AS UserContributionCategory,
    COALESCE(ue.Location, 'Unspecified Location') AS DisplayLocation,
    CASE WHEN (ue.UpVotes + ue.DownVotes) = 0 THEN NULL ELSE CAST(ue.UpVotes AS NUMERIC) / CAST((ue.UpVotes + ue.DownVotes) AS NUMERIC) END AS NetVoteRatio,
    SUBSTR(ue.AboutMe, 1, 100) AS AboutMeExcerpt,
    LOWER(REPLACE(ue.DisplayName, ' ', '-')) AS DisplayNameSlug,
    EXISTS (
        SELECT 1 FROM Posts p_inner
        WHERE p_inner.OwnerUserId = ue.UserId
          AND p_inner.PostTypeId = 1
          AND p_inner.Tags LIKE '%<sql>%'
          AND p_inner.ViewCount > 5000
          AND p_inner.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
    ) AS HasRecentHighViewSQLQuestions
FROM UserEngagement ue
LEFT JOIN PostAggregates pa ON ue.UserId = pa.UserId
LEFT JOIN (
    SELECT
        p_ans.OwnerUserId AS AnswerOwnerUserId,
        SUM(aa.QuestionsAcceptedThisAnswerFor) AS TotalAcceptedAnswersContributed
    FROM AnswerAcceptance aa
    JOIN Posts p_ans ON aa.AnswerId = p_ans.Id
    WHERE p_ans.OwnerUserId IS NOT NULL
    GROUP BY p_ans.OwnerUserId
) accepted_ans_owner ON ue.UserId = accepted_ans_owner.AnswerOwnerUserId
LEFT JOIN RankedUserTags tgs ON ue.UserId = tgs.UserId AND tgs.rn = 1
LEFT JOIN (
    SELECT
        phe.EditorUserId AS UserId,
        SUM(phe.EditEvents) AS TotalUserEditEvents,
        AVG(phe.AvgBodyContentLengthChange) AS AvgEditContentLength
    FROM PostHistoryEditAnalysis phe
    GROUP BY phe.EditorUserId
) ph_user_summary ON ue.UserId = ph_user_summary.UserId
LEFT JOIN (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalUserComments,
        AVG(CAST(c.Score AS NUMERIC)) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
) comm_agg ON ue.UserId = comm_agg.UserId
CROSS JOIN OverallAverages oa
WHERE
    ue.AccountActiveDays > 90
    AND (ue.Location IS NOT NULL AND (LOWER(ue.Location) LIKE '%europe%' OR LOWER(ue.Location) LIKE '%america%' OR LOWER(ue.Location) LIKE '%asia%'))
    AND ((pa.AnswersProvided IS NOT NULL AND pa.AnswersProvided > 0) OR ue.GoldBadges > 2)
    AND ue.Reputation >= 1500
ORDER BY
    GlobalUserRankByActivity ASC, ue.Reputation DESC, AcceptedAnswersContributedByThisUser DESC
LIMIT 5000;