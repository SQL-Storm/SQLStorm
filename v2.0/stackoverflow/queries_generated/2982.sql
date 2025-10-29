-- {"query": "2982.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2377} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1),0) AS QuestionsAsked,
        COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2),0) AS AnswersGiven,
        COALESCE(SUM(v.VoteTypeId = 2)::int,0) AS UpVotesReceived,
        COALESCE(SUM(v.VoteTypeId = 3)::int,0) AS DownVotesReceived,
        MAX(b.Date) FILTER (WHERE b.Class = 1) AS LastGoldBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 2) AS LastSilverBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 3) AS LastBronzeBadgeDate,
        COUNT(DISTINCT c.Id) AS CommentsMade
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostLinkInfo AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p1.PostTypeId AS PostType,
        p2.PostTypeId AS RelatedPostType
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
),
TaggedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        regexp_split_to_table(
            substring(p.Tags, 2, length(p.Tags) - 2),
            '><'
        ) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT Tag, COUNT(*) AS TagCount
    FROM TaggedPosts
    GROUP BY Tag
    ORDER BY TagCount DESC
    LIMIT 10
),
UserTopTags AS (
    SELECT
        ua.UserId,
        t.Tag,
        COUNT(*) AS PostsInTag
    FROM
        UserActivity ua
        JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
        JOIN TaggedPosts t ON t.PostId = p.Id
    WHERE t.Tag IN (SELECT Tag FROM TopTags)
    GROUP BY ua.UserId, t.Tag
),
RankedUserTags AS (
    SELECT
        utt.UserId,
        utt.Tag,
        utt.PostsInTag,
        RANK() OVER (PARTITION BY utt.UserId ORDER BY utt.PostsInTag DESC) AS TagRank
    FROM UserTopTags utt
),
RecentPostHistoryEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
LatestPostEdits AS (
    SELECT
        rph.PostId,
        rph.UserId,
        rph.PostHistoryTypeId,
        rph.CreationDate
    FROM RecentPostHistoryEdits rph
    WHERE rph.rn = 1
),
QuestionsWithAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COALESCE(q.AnswerCount,0) AS AnswerCount,
        COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
        q.AcceptedAnswerId,
        a.TopAnswerId,
        a.TopAnswerScore
    FROM Posts q
    LEFT JOIN (
        SELECT
            p.ParentId,
            AVG(p.Score) AS AvgAnswerScore,
            MAX(p.Score) AS TopAnswerScore,
            MAX(p.Id) FILTER (WHERE p.Score = MAX(p.Score) OVER (PARTITION BY p.ParentId)) AS TopAnswerId
        FROM Posts p
        WHERE p.PostTypeId = 2
        GROUP BY p.ParentId
    ) a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
UserEngagement AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.CommentsMade,
        COALESCE(utt.PostsInTag, 0) AS PostsInTopTag,
        utt.Tag AS TopTag,
        COALESCE(bGold.GoldBadges, 0) AS GoldBadges,
        COALESCE(bSilver.SilverBadges, 0) AS SilverBadges,
        COALESCE(bBronze.BronzeBadges, 0) AS BronzeBadges
    FROM UserActivity ua
    LEFT JOIN (
        SELECT
            UserId,
            Tag,
            PostsInTag,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY PostsInTag DESC) AS rn
        FROM UserTopTags
    ) utt ON utt.UserId = ua.UserId AND utt.rn = 1
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS GoldBadges FROM Badges WHERE Class = 1 GROUP BY UserId
    ) bGold ON bGold.UserId = ua.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS SilverBadges FROM Badges WHERE Class = 2 GROUP BY UserId
    ) bSilver ON bSilver.UserId = ua.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BronzeBadges FROM Badges WHERE Class = 3 GROUP BY UserId
    ) bBronze ON bBronze.UserId = ua.UserId
    WHERE ua.Reputation > 1000
),
AggregatedAnswers AS (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(*) AS AnswerCount,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS HighScoreAnswers
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
HighImpactUsers AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.QuestionsAsked,
        COALESCE(aa.AnswerCount, 0) AS AnswerCount,
        ue.UpVotesReceived,
        ue.DownVotesReceived,
        ue.CommentsMade,
        COALESCE(aa.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(aa.HighScoreAnswers, 0) AS HighScoreAnswers,
        ue.TopTag,
        ue.PostsInTopTag,
        ue.GoldBadges,
        ue.SilverBadges,
        ue.BronzeBadges
    FROM UserEngagement ue
    LEFT JOIN AggregatedAnswers aa ON aa.OwnerUserId = ue.UserId
    WHERE COALESCE(aa.AnswerCount,0) > 5
),
FinalRanking AS (
    SELECT
        hiu.*,
        ROW_NUMBER() OVER (
            ORDER BY
                hiu.Reputation DESC,
                hiu.GoldBadges DESC,
                hiu.AnswerCount DESC,
                hiu.UpVotesReceived DESC
        ) AS Rank
    FROM HighImpactUsers hiu
),
DuplicateQuestionPairs AS (
    SELECT
        pl.PostId AS OriginalQuestionId,
        pl.RelatedPostId AS DuplicateQuestionId,
        pq.Title AS OriginalTitle,
        pd.Title AS DuplicateTitle,
        pl.CreationDate,
        u.DisplayName AS DuplicatorUser
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name = 'Duplicate'
    JOIN Posts pq ON pq.Id = pl.PostId AND pq.PostTypeId = 1
    JOIN Posts pd ON pd.Id = pl.RelatedPostId AND pd.PostTypeId = 1
    LEFT JOIN Users u ON u.Id = pd.OwnerUserId
    WHERE pl.CreationDate > NOW() - INTERVAL '1 year'
),
CorrelatedVotes AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        (SELECT COUNT(1) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(1) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCount,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
PostsWithRecentEdits AS (
    SELECT
        p.PostId,
        p.Title,
        p.Score,
        lpe.PostHistoryTypeId,
        lpe.UserId AS EditorUserId,
        u.DisplayName AS EditorName,
        lpe.CreationDate AS EditDate
    FROM QuestionsWithAnswerStats p
    LEFT JOIN LatestPostEdits lpe ON lpe.PostId = p.PostId
    LEFT JOIN Users u ON u.Id = lpe.UserId
)
SELECT
    fr.Rank,
    fr.DisplayName,
    fr.Reputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.AnswerCount,
    fr.UpVotesReceived,
    fr.DownVotesReceived,
    fr.CommentsMade,
    fr.TopTag,
    fr.PostsInTopTag,
    dq.OriginalQuestionId,
    dq.OriginalTitle,
    dq.DuplicateQuestionId,
    dq.DuplicateTitle,
    dq.CreationDate AS DuplicateLinkDate,
    dq.DuplicatorUser,
    cv.PostId,
    cv.Title AS PostTitle,
    cv.PostTypeId,
    cv.Score AS PostScore,
    cv.UpvoteCount,
    cv.DownvoteCount,
    cv.CommentCount,
    pwe.PostHistoryTypeId,
    pwe.EditorUserId,
    pwe.EditorName,
    pwe.EditDate
FROM FinalRanking fr
LEFT JOIN DuplicateQuestionPairs dq ON dq.DuplicatorUser = fr.DisplayName
LEFT JOIN CorrelatedVotes cv ON cv.PostId = (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fr.UserId ORDER BY p.Score DESC LIMIT 1
)
LEFT JOIN PostsWithRecentEdits pwe ON pwe.PostId = cv.PostId
WHERE fr.Rank <= 50
ORDER BY fr.Rank, dq.CreationDate DESC NULLS LAST;
