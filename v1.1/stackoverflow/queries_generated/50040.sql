-- {"query": "50040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1124} 

WITH QuestionTags AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.FavoriteCount,
        tag.name AS TagName
    FROM Posts AS p,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag(name)
    WHERE p.PostTypeId = 1 -- Question
      AND p.ClosedDate IS NULL
      AND p.AnswerCount > 1
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswererId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.CommentCount AS AnswerCommentCount,
        q.QuestionId,
        q.TagName,
        q.QuestionOwnerId,
        q.QuestionCreationDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.QuestionCreationDate)) AS TimeToAnswerSeconds
    FROM Posts AS a
    JOIN QuestionTags AS q ON a.ParentId = q.QuestionId
    WHERE a.PostTypeId = 2 -- Answer
      AND a.OwnerUserId IS NOT NULL
),
UserTagPerformance AS (
    SELECT
        ad.AnswererId,
        ad.TagName,
        COUNT(*) AS AnswersInTag,
        AVG(ad.AnswerScore) AS AvgScoreInTag,
        SUM(ad.AnswerScore) AS TotalScoreInTag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ad.TimeToAnswerSeconds) AS MedianTimeToAnswer,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM AnswerDetails AS ad
    LEFT JOIN Votes AS v ON ad.AnswerId = v.PostId
    GROUP BY ad.AnswererId, ad.TagName
    HAVING COUNT(*) > 10 AND SUM(ad.AnswerScore) > 20
),
RankedUserPerformance AS (
    SELECT
        utp.AnswererId,
        utp.TagName,
        utp.AnswersInTag,
        utp.AvgScoreInTag,
        utp.TotalScoreInTag,
        utp.MedianTimeToAnswer,
        (utp.TotalUpvotes - utp.TotalDownvotes) AS NetVotes,
        RANK() OVER (PARTITION BY utp.TagName ORDER BY utp.TotalScoreInTag DESC, utp.MedianTimeToAnswer ASC) AS RankInTag,
        DENSE_RANK() OVER (PARTITION BY utp.AnswererId ORDER BY utp.TotalScoreInTag DESC) AS UserBestTagRank
    FROM UserTagPerformance AS utp
),
UserAggregates AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Comments WHERE UserId = u.Id) AS TotalCommentsMade,
        SUM(rup.AnswersInTag) AS TotalRankedAnswers,
        AVG(rup.AvgScoreInTag) AS OverallAvgAnswerScore,
        SUM(rup.NetVotes) AS OverallNetVotes,
        string_agg(CASE WHEN rup.UserBestTagRank <= 3 THEN rup.TagName || ' (Rank:' || rup.RankInTag || ')' ELSE NULL END, ' | ') AS TopTags
    FROM Users AS u
    JOIN RankedUserPerformance AS rup ON u.Id = rup.AnswererId
    WHERE u.Reputation > 10000
      AND rup.RankInTag <= 50 -- Only consider users who are in the top 50 of at least one tag
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.TotalRankedAnswers,
    ua.OverallNetVotes,
    ua.TopTags,
    (ua.Reputation * 0.5 + ua.OverallNetVotes * 2 + ua.GoldBadges * 1000 + ua.SilverBadges * 200) / (LOG(ua.Views + 10)) AS FinalScore
FROM UserAggregates AS ua
WHERE ua.TotalRankedAnswers > 50 AND ua.TopTags IS NOT NULL
ORDER BY FinalScore DESC
LIMIT 200;
