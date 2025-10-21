-- {"query": "48099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1079} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.Score DESC, p.CreationDate DESC) AS FavoriteRank
    FROM Posts AS p
    WHERE p.PostTypeId = 1 -- Only consider questions for this analysis
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT v.PostId) AS TotalVotesCast,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotes,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEntries,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        u.CreationDate AS UserCreationDate
    FROM Users AS u
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    LEFT JOIN VoteTypes AS vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagPerformance AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionsWithTag,
        AVG(CAST(p.Score AS REAL)) AS AverageScore,
        AVG(CAST(p.ViewCount AS REAL)) AS AverageViewCount,
        AVG(CAST(p.FavoriteCount AS REAL)) AS AverageFavoriteCount,
        MAX(p.CreationDate) AS LatestQuestionDate
    FROM Tags AS t
    JOIN Posts AS p ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 100 -- Only consider tags with a significant number of questions
)
SELECT
    rp.PostId,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.ViewRank,
    rp.ScoreRank,
    rp.FavoriteRank,
    ua.Reputation AS OwnerReputation,
    ua.TotalVotesCast AS OwnerTotalVotesCast,
    ua.TotalUpVotes AS OwnerTotalUpVotes,
    ua.TotalDownVotes AS OwnerTotalDownVotes,
    ua.TotalComments AS OwnerTotalComments,
    ua.TotalPostHistoryEntries AS OwnerTotalPostHistoryEntries,
    STRING_AGG(tp.TagName, ', ') WITHIN GROUP (ORDER BY tp.QuestionsWithTag DESC) AS TopTags,
    SUM(tp.AverageScore) OVER (ORDER BY rp.ScoreRank ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAverageTagScore
FROM RankedPosts AS rp
JOIN Users AS u ON rp.Id = u.Id -- Assuming OwnerUserId is the user who created the post, which is not explicitly linked, but often implied. Adjust if schema differs.
JOIN UserActivity AS ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN Posts AS p_tags ON rp.Id = p_tags.Id -- Join to extract tags for tag performance
LEFT JOIN TagPerformance AS tp ON tp.TagName = ANY(string_to_array(substring(p_tags.Tags, 2, length(p_tags.Tags)-2), '><'))
GROUP BY rp.PostId, rp.Score, rp.ViewCount, rp.FavoriteCount, rp.AnswerCount, rp.CommentCount, rp.ViewRank, rp.ScoreRank, rp.FavoriteRank, ua.Reputation, ua.TotalVotesCast, ua.TotalUpVotes, ua.TotalDownVotes, ua.TotalComments, ua.TotalPostHistoryEntries
ORDER BY rp.ScoreRank, rp.ViewRank, rp.FavoriteRank
LIMIT 1000;
