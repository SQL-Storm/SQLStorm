-- {"query": "52018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 920} 
WITH user_stats AS (
    SELECT u.Id, u.Reputation, u.CreationDate AS UserCreationDate,
           COUNT(DISTINCT b.Id) AS TotalBadges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
post_stats AS (
    SELECT p.OwnerUserId,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
           SUM(p.Score) AS TotalScore,
           AVG(p.Score) AS AvgScore,
           MAX(p.CreationDate) AS LatestPostDate,
           COUNT(DISTINCT pl.Id) AS LinkedPosts,
           COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS DuplicateLinks
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
vote_stats AS (
    SELECT v.UserId,
           COUNT(DISTINCT v.Id) AS TotalVotesCast,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesGiven,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven,
           SUM(CASE WHEN vt.Name = 'BountyStart' THEN v.BountyAmount ELSE 0 END) AS BountiesStarted,
           SUM(CASE WHEN vt.Name = 'BountyClose' THEN v.BountyAmount ELSE 0 END) AS BountiesClosed
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
comment_stats AS (
    SELECT c.UserId,
           COUNT(DISTINCT c.Id) AS CommentsPosted,
           AVG(c.Score) AS AvgCommentScore,
           MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
edit_history AS (
    SELECT ph.UserId,
           COUNT(DISTINCT ph.Id) AS TotalEdits,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS EditsMade,
           AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))/86400) AS AvgDaysToEdit
    FROM PostHistory ph
    INNER JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
)
SELECT us.Id, us.Reputation, us.UserCreationDate, us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
       ps.QuestionsPosted, ps.AnswersPosted, ps.TotalScore, ps.AvgScore, ps.LatestPostDate, ps.LinkedPosts, ps.DuplicateLinks,
       vs.TotalVotesCast, vs.UpVotesGiven, vs.DownVotesGiven, vs.BountiesStarted, vs.BountiesClosed,
       cs.CommentsPosted, cs.AvgCommentScore, cs.LatestCommentDate,
       eh.TotalEdits, eh.EditsMade, eh.AvgDaysToEdit
FROM user_stats us
LEFT JOIN post_stats ps ON us.Id = ps.OwnerUserId
LEFT JOIN vote_stats vs ON us.Id = vs.UserId
LEFT JOIN comment_stats cs ON us.Id = cs.UserId
LEFT JOIN edit_history eh ON us.Id = eh.UserId
WHERE us.TotalBadges > 0 AND ps.QuestionsPosted > 0
ORDER BY us.Reputation DESC, ps.TotalScore DESC
LIMIT 100;