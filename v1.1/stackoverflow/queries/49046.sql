-- {"query": "49046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1647} 
WITH UserPostAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalQuestionViews,
        SUM(COALESCE(p.CommentCount, 0)) AS TotalPostComments,
        SUM(CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND (
                '<sql>' = ANY(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) OR
                '<python>' = ANY(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) OR
                '<javascript>' = ANY(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
            ) THEN 1
            ELSE 0
        END) AS PopularTagPosts,
        COUNT(CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN p.Id END) AS AcceptedAnswersReceived
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Name ELSE NULL END) AS DistinctTagBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS UpvotedCommentsMade
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserPostHistoryEdits AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalPostHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS PostEditsMade,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS PostRollbacksMade,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS PostClosuresDeletions
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserVoteReceivedSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceivedOnPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceivedOnPosts,
        COUNT(DISTINCT v.PostId) AS UniquePostsVotedOn
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes AS UserProfileUpVotesGiven,
    u.DownVotes AS UserProfileDownVotesGiven,
    COALESCE(upa.TotalPosts, 0) AS TotalPosts,
    COALESCE(upa.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(upa.AnswersGiven, 0) AS AnswersGiven,
    COALESCE(upa.AvgPostScore, 0.0) AS AvgPostScore,
    COALESCE(upa.PopularTagPosts, 0) AS PopularTagPostsCount,
    COALESCE(upa.AcceptedAnswersReceived, 0) AS AcceptedAnswersGiven,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.DistinctTagBadges, 0) AS DistinctTagBadges,
    COALESCE(uca.TotalCommentsMade, 0) AS CommentsMade,
    COALESCE(uca.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(uphe.PostEditsMade, 0) AS PostEditsMade,
    COALESCE(uphe.PostRollbacksMade, 0) AS PostRollbacksMade,
    COALESCE(uvrs.UpVotesReceivedOnPosts, 0) AS UpVotesReceivedOnPosts,
    COALESCE(uvrs.DownVotesReceivedOnPosts, 0) AS DownVotesReceivedOnPosts,
    RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(upa.AvgPostScore, 0.0) DESC, COALESCE(ubs.GoldBadges, 0) DESC) AS OverallRank,
    NTILE(10) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationDecile
FROM Users u
LEFT JOIN UserPostAggregates upa ON u.Id = upa.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserPostHistoryEdits uphe ON u.Id = uphe.UserId
LEFT JOIN UserVoteReceivedSummary uvrs ON u.Id = uvrs.UserId
WHERE
    u.Reputation > 5000
    AND u.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years')
    AND (
        COALESCE(upa.PopularTagPosts, 0) > 10
        OR COALESCE(ubs.GoldBadges, 0) >= 1
        OR COALESCE(upa.AvgPostScore, 0.0) > 10
        OR COALESCE(uca.TotalCommentsMade, 0) > 50
    )
ORDER BY
    OverallRank ASC,
    u.Reputation DESC,
    COALESCE(upa.TotalPosts, 0) DESC,
    u.CreationDate ASC
LIMIT 200;