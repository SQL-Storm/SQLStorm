-- {"query": "2858.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1728} 
WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.Score, 0) AS PostScore,
        u.Reputation AS OwnerReputation,
        u.DisplayName AS OwnerDisplayName
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        rh.PostViewCount + COALESCE(p.ViewCount, 0),
        rh.PostScore + COALESCE(p.Score, 0),
        u.Reputation,
        u.DisplayName
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy rh ON t.Id = rh.Id
    LEFT JOIN Posts p ON p.Id = t.WikiPostId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 1
),
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankByLocation
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE u.Location IS NOT NULL
),
PostComplexity AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(pl.LinkCount, 0) AS LinkCount,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        p.CreationDate,
        p.LastActivityDate,
        rnk.DenseRank,
        CASE
            WHEN p.PostTypeId = 1 THEN COALESCE((SELECT COUNT(*) FROM Posts ans WHERE ans.ParentId = p.Id AND ans.Score > p.Score / NULLIF(NULLIF((SELECT AVG(Score) FROM Posts WHERE ParentId = p.Id),0),0)), 0)
            ELSE 0
        END AS CompetitiveAnswerCount,
        CASE
            WHEN p.Tags IS NOT NULL THEN
                array_length(string_to_array(trim(both '<>' from p.Tags), '><'), 1)
            ELSE 0
        END AS TagCount,
        -- Complex string manipulation and NULL handling example
        COALESCE(NULLIF(TRIM(REPLACE(REPLACE(p.Body, '<code>', ''), '</code>', '')), ''), '[no body text]') AS CleanedBodySnippet
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS LinkCount
        FROM PostLinks
        GROUP BY PostId
    ) pl ON p.Id = pl.PostId
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    CROSS JOIN LATERAL (
        SELECT DENSE_RANK() OVER (ORDER BY p.Score DESC) AS DenseRank
    ) rnk
    WHERE p.PostTypeId IN (1, 2)
),
TopQuestionsWithAnswers AS (
    SELECT 
        pc.Id AS QuestionId,
        pc.Title AS QuestionTitle,
        pc.Score AS QuestionScore,
        pc.ViewCount AS QuestionViews,
        pc.TagCount,
        pc.LinkCount AS QuestionLinkCount,
        pc.UpVotes AS QuestionUpVotes,
        pc.DownVotes AS QuestionDownVotes,
        ua.Id AS AnswerId,
        ua.Title AS AnswerTitle,
        ua.Score AS AnswerScore,
        ua.CommentCount AS AnswerComments,
        ua.UpVotes AS AnswerUpVotes,
        ua.DownVotes AS AnswerDownVotes,
        us.DisplayName AS AuthorDisplayName,
        us.Reputation AS AuthorReputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        pc.CompetitiveAnswerCount,
        ROW_NUMBER() OVER (PARTITION BY pc.Id ORDER BY ua.Score DESC, ua.CreationDate ASC) AS AnswerRank
    FROM PostComplexity pc
    LEFT JOIN Posts ua ON ua.ParentId = pc.Id AND ua.PostTypeId = 2
    LEFT JOIN Users u ON pc.OwnerUserId = u.Id
    LEFT JOIN UserStats us ON us.Id = ua.OwnerUserId
    WHERE pc.PostTypeId = 1
),
FilteredAnswers AS (
    SELECT *
    FROM TopQuestionsWithAnswers
    WHERE AnswerRank <= 3
),
UserBadgesWithRecentActivity AS (
    SELECT 
        b.UserId,
        COUNT(*) AS RecentBadgesCount,
        MAX(b.Date) AS MostRecentBadgeDate
    FROM Badges b
    WHERE b.Date > CURRENT_DATE - INTERVAL '90 days'
    GROUP BY b.UserId
),
PostsWithLatestComments AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        c.Text AS LatestCommentText,
        c.UserDisplayName AS LatestCommentUser,
        c.CreationDate AS LatestCommentDate
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT c.Text, c.UserDisplayName, c.CreationDate
        FROM Comments c
        WHERE c.PostId = p.Id
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) c ON TRUE
)
SELECT 
    f.AnswerId,
    f.AnswerTitle,
    f.AnswerScore,
    f.AnswerComments,
    f.AnswerUpVotes,
    f.AnswerDownVotes,
    f.QuestionId,
    f.QuestionTitle,
    f.QuestionScore,
    f.QuestionViews,
    f.TagCount,
    f.QuestionLinkCount,
    f.QuestionUpVotes,
    f.QuestionDownVotes,
    f.AuthorDisplayName,
    f.AuthorReputation,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.CompetitiveAnswerCount,
    uba.RecentBadgesCount,
    uba.MostRecentBadgeDate,
    pt.LatestCommentText,
    pt.LatestCommentUser,
    pt.LatestCommentDate,
    -- Example of correlated subquery with NULL handling and string concatenation
    (
        SELECT STRING_AGG(DISTINCT CONCAT(uh.TagName, ':', uh.PostScore), ', ' ORDER BY uh.PostScore DESC)
        FROM RecursiveTagHierarchy uh
        WHERE uh.PostViewCount > 1000 AND uh.OwnerReputation > 1000
        LIMIT 5
    ) AS PopularTagsSummary
FROM FilteredAnswers f
LEFT JOIN UserBadgesWithRecentActivity uba ON f.AuthorDisplayName = uba.UserId
LEFT JOIN PostsWithLatestComments pt ON pt.PostId = f.QuestionId
WHERE (f.QuestionScore > 10 OR f.AnswerScore > 5)
  AND (f.AnswerScore IS NOT NULL AND f.AnswerScore >= 0)
ORDER BY f.QuestionScore DESC, f.AnswerScore DESC, f.AnswerComments DESC;