-- {"query": "926.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1532} 

WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, 1 AS Level,
           CAST(t.TagName AS VARCHAR(1000)) AS FullHierarchy
    FROM Tags t
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT child.Id, child.TagName, child.Count, parent.Level + 1,
           parent.FullHierarchy || ' > ' || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.WikiPostId = parent.Id
    WHERE child.IsRequired = 1
),
UserBadgeStats AS (
    SELECT u.Id AS UserId, u.DisplayName,
           COUNT(b.Id) AS TotalBadges,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT q.Id AS QuestionId, q.Title, q.OwnerUserId, q.CreationDate,
           COUNT(a.Id) AS AnswerCount,
           AVG(COALESCE(a.Score,0)) AS AvgAnswerScore,
           MAX(a.Score) AS MaxAnswerScore,
           MIN(a.Score) AS MinAnswerScore,
           SUM(CASE WHEN a.Score IS NULL THEN 0 ELSE 1 END) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS AnsweredByUsers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
PostVotesAgg AS (
    SELECT p.Id AS PostId,
           COUNT(v.Id) AS TotalVotes,
           COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
           COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
           SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY p.Id
),
UserActivityRanked AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           RANK() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationRank,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
           COUNT(DISTINCT c.Id) AS CommentsMade
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
DuplicatesWithLinked AS (
    SELECT pl.PostId, pl.RelatedPostId,
           p1.Title AS PostTitle, p2.Title AS RelatedPostTitle,
           lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE lt.Name IN ('Duplicate', 'Linked')
),
ClosedQuestionsWithReasons AS (
    SELECT ph.PostId, MAX(ph.CreationDate) AS ClosedDate,
           STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId
)
SELECT 
    uar.DisplayName AS User,
    uar.Reputation,
    uar.ReputationRank,
    uar.QuestionsAsked,
    uar.AnswersGiven,
    uar.CommentsMade,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    COALESCE(pas.AnswerCount,0) AS TotalAnswersOnQuestionsByUser,
    COALESCE(pas.AvgAnswerScore,0) AS AvgAnswerScoreOnUserQuestions,
    COALESCE(pv.TotalVotes,0) AS TotalVotesOnUserPosts,
    pv.UpVotes, pv.DownVotes, pv.TotalBounty,
    string_agg(DISTINCT rth.FullHierarchy, '; ') FILTER (WHERE rth.Level IS NOT NULL) AS UserTagHierarchy,
    dq.PostTitle AS DuplicateQuestion,
    dq.RelatedPostTitle AS OriginalQuestionLinked,
    dq.LinkTypeName,
    cqwr.CloseReasons,
    cqwr.ClosedDate
FROM UserActivityRanked uar
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = uar.Id
LEFT JOIN PostAnswerStats pas ON pas.OwnerUserId = uar.Id
LEFT JOIN Posts p_user_posts ON p_user_posts.OwnerUserId = uar.Id
LEFT JOIN PostVotesAgg pv ON pv.PostId = p_user_posts.Id
LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName = ANY(
    SELECT unnest(string_to_array(
        COALESCE(p_user_posts.Tags,'')
        , '><'
    ))
)
LEFT JOIN LATERAL (
    SELECT dqinner.PostTitle, dqinner.RelatedPostTitle, dqinner.LinkTypeName
    FROM DuplicatesWithLinked dqinner
    WHERE dqinner.PostId IN (
        SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = uar.Id AND p_inner.PostTypeId = 1
    )
    ORDER BY dqinner.PostId LIMIT 1
) dq ON TRUE
LEFT JOIN ClosedQuestionsWithReasons cqwr ON cqwr.PostId IN (
    SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = uar.Id AND p_inner.PostTypeId = 1
)
GROUP BY uar.DisplayName, uar.Reputation, uar.ReputationRank, uar.QuestionsAsked, uar.AnswersGiven, uar.CommentsMade,
         ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBasedBadges,
         pas.AnswerCount, pas.AvgAnswerScore,
         pv.TotalVotes, pv.UpVotes, pv.DownVotes, pv.TotalBounty,
         dq.PostTitle, dq.RelatedPostTitle, dq.LinkTypeName,
         cqwr.CloseReasons, cqwr.ClosedDate
ORDER BY uar.Reputation DESC NULLS LAST
LIMIT 50;
