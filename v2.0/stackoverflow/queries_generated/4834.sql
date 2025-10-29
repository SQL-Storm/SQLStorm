-- {"query": "4834.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1155} 
WITH PostEditCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(ph.Id) AS EditCount
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY p.OwnerUserId
),
UserPostSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        u.CreationDate AS UserCreationDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedEdits AS (
    SELECT
        pec.OwnerUserId,
        pec.EditCount,
        ROW_NUMBER() OVER (ORDER BY pec.EditCount DESC) AS EditRank
    FROM PostEditCounts pec
),
TagPopularity AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount,
        SUM(p.AnswerCount) AS TotalAnswersForTag,
        AVG(p.FavoriteCount) AS AverageFavoriteCount
    FROM Tags t
    JOIN Posts p ON t.TagName IN (SELECT TRIM(LOWER(unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))))
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != ''
    GROUP BY t.TagName
),
TopTags AS (
    SELECT
        TagName,
        PostCount,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) AS TagRank
    FROM TagPopularity
    WHERE PostCount > 1000
),
UserActivity AS (
    SELECT
        u.Id,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    GROUP BY u.Id
)
SELECT
    ups.DisplayName,
    ups.Reputation,
    ups.UserCreationDate,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    COALESCE(ups.AveragePostScore, 0.0) AS AveragePostScore,
    ups.LatestPostDate,
    COALESCE(re.EditCount, 0) AS TotalEdits,
    re.EditRank,
    ua.CommentCount,
    ua.VoteCount,
    CASE
        WHEN ups.LatestPostDate > ups.UserCreationDate + INTERVAL '1 year' THEN 'Experienced'
        WHEN ups.LatestPostDate > ups.UserCreationDate + INTERVAL '3 months' THEN 'Intermediate'
        ELSE 'New'
    END AS UserExperienceLevel,
    STRING_AGG(tt.TagName, ', ') AS TopTags
FROM UserPostSummary ups
LEFT JOIN RankedEdits re ON ups.UserId = re.OwnerUserId
LEFT JOIN UserActivity ua ON ups.UserId = ua.Id
LEFT JOIN Posts p_latest ON ups.UserId = p_latest.OwnerUserId AND p_latest.Id = (
    SELECT Id
    FROM Posts
    WHERE OwnerUserId = ups.UserId
    ORDER BY CreationDate DESC
    LIMIT 1
)
LEFT JOIN (
    SELECT DISTINCT
        t.TagName,
        p.OwnerUserId
    FROM Tags t
    JOIN Posts p ON t.TagName IN (SELECT TRIM(LOWER(unnest(string_to_array(substring(p_inner.Tags, 2, length(p_inner.Tags)-2), '><')))))
    CROSS JOIN Posts p_inner
    WHERE p_inner.OwnerUserId = ups.UserId
) AS user_tags ON ups.UserId = user_tags.OwnerUserId
LEFT JOIN TopTags tt ON user_tags.TagName = tt.TagName
GROUP BY
    ups.DisplayName,
    ups.Reputation,
    ups.UserCreationDate,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AveragePostScore,
    ups.LatestPostDate,
    re.EditCount,
    re.EditRank,
    ua.CommentCount,
    ua.VoteCount
HAVING
    ups.TotalPosts > 10 AND ups.Reputation > 500
ORDER BY
    ups.Reputation DESC, ups.LatestPostDate DESC
LIMIT 100;