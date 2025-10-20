-- {"query": "55099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1449} 

WITH RECURSIVE
    -- 1. Gather the most recent activity (post, comment, vote) per user
    recent_activity AS (
        SELECT u.Id               AS UserId,
               MAX(p.LastActivityDate)  AS LastPostActivity,
               MAX(c.CreationDate)      AS LastCommentActivity,
               MAX(v.CreationDate)      AS LastVoteActivity
        FROM   Users u
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Votes v    ON v.UserId = u.Id
        GROUP BY u.Id
    ),

    -- 2. Aggregate badge counts per user, split by class and tag‑based flag
    badge_agg AS (
        SELECT b.UserId,
               SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
               SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
               SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
               SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
        FROM   Badges b
        GROUP BY b.UserId
    ),

    -- 3. Compute post‑level statistics for each user (questions vs answers)
    user_posts AS (
        SELECT p.OwnerUserId                                 AS UserId,
               COUNT(*) FILTER (WHERE p.PostTypeId = 1)      AS QuestionsAsked,
               COUNT(*) FILTER (WHERE p.PostTypeId = 2)      AS AnswersGiven,
               SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)  AS QuestionScoreSum,
               SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)  AS AnswerScoreSum,
               AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionViews,
               COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAccepted
        FROM   Posts p
        WHERE  p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- 4. Extract tag usage from questions and rank the most common tags per user
    user_tags AS (
        SELECT p.OwnerUserId                                   AS UserId,
               UNNEST(string_to_array(
                     SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2),
                     '><'))                                   AS Tag
        FROM   Posts p
        WHERE  p.PostTypeId = 1
          AND  p.Tags IS NOT NULL
    ),
    tag_counts AS (
        SELECT ut.UserId,
               ut.Tag,
               COUNT(*) AS TagUseCount,
               ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY COUNT(*) DESC) AS TagRank
        FROM   user_tags ut
        GROUP  BY ut.UserId, ut.Tag
    ),
    top_user_tags AS (
        SELECT UserId,
               STRING_AGG(Tag, ', ') FILTER (WHERE TagRank <= 3) AS TopThreeTags
        FROM   tag_counts
        GROUP  BY UserId
    ),

    -- 5. Vote aggregates per user (excluding self‑votes, i.e., votes on own posts)
    vote_agg AS (
        SELECT p.OwnerUserId                                           AS UserId,
               COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)           AS UpVotesReceived,
               COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)           AS DownVotesReceived,
               COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5)           AS FavoritesReceived
        FROM   Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
                         AND v.UserId <> p.OwnerUserId
        WHERE  p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- 6. Combine all user‑level pieces
    user_profile AS (
        SELECT u.Id                                 AS UserId,
               u.DisplayName,
               u.Reputation,
               ra.LastPostActivity,
               ra.LastCommentActivity,
               ra.LastVoteActivity,
               COALESCE(b.GoldBadges,0)              AS GoldBadges,
               COALESCE(b.SilverBadges,0)            AS SilverBadges,
               COALESCE(b.BronzeBadges,0)            AS BronzeBadges,
               COALESCE(b.TagBasedBadges,0)          AS TagBasedBadges,
               COALESCE(up.QuestionsAsked,0)         AS QuestionsAsked,
               COALESCE(up.AnswersGiven,0)           AS AnswersGiven,
               COALESCE(up.QuestionScoreSum,0)       AS QuestionScoreSum,
               COALESCE(up.AnswerScoreSum,0)         AS AnswerScoreSum,
               COALESCE(up.AvgQuestionViews,0)       AS AvgQuestionViews,
               COALESCE(up.QuestionsWithAccepted,0)  AS QuestionsWithAccepted,
               COALESCE(vu.UpVotesReceived,0)        AS UpVotesReceived,
               COALESCE(vu.DownVotesReceived,0)      AS DownVotesReceived,
               COALESCE(vu.FavoritesReceived,0)      AS FavoritesReceived,
               t.TopThreeTags
        FROM   Users u
        LEFT JOIN recent_activity ra   ON ra.UserId = u.Id
        LEFT JOIN badge_agg b          ON b.UserId = u.Id
        LEFT JOIN user_posts up        ON up.UserId = u.Id
        LEFT JOIN vote_agg vu          ON vu.UserId = u.Id
        LEFT JOIN top_user_tags t      ON t.UserId = u.Id
    )

SELECT *
FROM   user_profile
WHERE  Reputation > 10000
ORDER BY (GoldBadges*100 + SilverBadges*10 + BronzeBadges) DESC,
         Reputation DESC,
         UpVotesReceived DESC
LIMIT  100;
