-- {"query": "18008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1685} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(CAST(DATE_PART('year', AGE(u.CreationDate)) * 365.25 + DATE_PART('doy', AGE(u.CreationDate)) AS NUMERIC)) AS AvgDaysSinceCreation,
        COUNT(CASE WHEN c.CreationDate > u.LastAccessDate THEN c.Id END) AS RecentComments
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v_up.Id) AS UpVoteCount,
        COUNT(DISTINCT v_down.Id) AS DownVoteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v_up ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2
    LEFT JOIN Votes v_down ON p.Id = v_down.PostId AND v_down.VoteTypeId = 3
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    WHERE p.CreationDate >= DATE('now', '-1 year')
    GROUP BY p.Id, p.Title, pt.Name, u.DisplayName, p.Score, p.ViewCount, p.FavoriteCount, p.ClosedDate
),
UserPostSummary AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.BadgeCount,
        ua.AvgDaysSinceCreation,
        ua.RecentComments,
        SUM(pe.Score) AS TotalPostScore,
        AVG(pe.ViewCount) AS AvgPostViewCount,
        SUM(pe.UpVoteCount) AS TotalUpVotesReceived,
        SUM(pe.DownVoteCount) AS TotalDownVotesReceived,
        COUNT(CASE WHEN pe.PostStatus = 'Closed' THEN pe.PostId END) AS ClosedPostCount
    FROM UserActivity ua
    JOIN PostEngagement pe ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pe.PostId)
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, ua.QuestionCount, ua.AnswerCount, ua.BadgeCount, ua.AvgDaysSinceCreation, ua.RecentComments
),
TopUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        AvgDaysSinceCreation,
        RecentComments,
        TotalPostScore,
        AvgPostViewCount,
        TotalUpVotesReceived,
        TotalDownVotesReceived,
        ClosedPostCount,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPostScore DESC) AS Rank
    FROM UserPostSummary
    WHERE TotalPostScore > 0
)
SELECT
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.BadgeCount,
    ROUND(tu.AvgDaysSinceCreation, 2) AS AvgDaysSinceCreation,
    tu.RecentComments,
    tu.TotalPostScore,
    ROUND(tu.AvgPostViewCount, 2) AS AvgPostViewCount,
    tu.TotalUpVotesReceived,
    tu.TotalDownVotesReceived,
    tu.ClosedPostCount,
    CASE
        WHEN tu.Rank <= 10 THEN 'Top 10% Contributor'
        WHEN tu.Rank <= (SELECT COUNT(*) FROM TopUsers) * 0.25 THEN 'Top 25% Contributor'
        WHEN tu.Rank <= (SELECT COUNT(*) FROM TopUsers) * 0.50 THEN 'Top 50% Contributor'
        ELSE 'Other Contributor'
    END AS ContributionTier,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    COALESCE(u.WebsiteUrl, 'No Website') AS UserWebsite,
    CASE
        WHEN AVG(pe.ViewCount) FILTER (WHERE pe.PostType = 'Question') > AVG(pe.ViewCount) FILTER (WHERE pe.PostType = 'Answer') THEN 'Questions get more views'
        WHEN AVG(pe.ViewCount) FILTER (WHERE pe.PostType = 'Question') < AVG(pe.ViewCount) FILTER (WHERE pe.PostType = 'Answer') THEN 'Answers get more views'
        ELSE 'Equal Views or No Data'
    END AS ViewDistribution,
    (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.UserId = tu.UserId AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits
    ) AS TotalEdits,
    (
        SELECT STRING_AGG(pht.Name, ', ')
        FROM PostHistory ph
        JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        WHERE ph.UserId = tu.UserId AND ph.CreationDate > DATE('now', '-30 days')
        GROUP BY ph.UserId
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS MostFrequentRecentAction
FROM TopUsers tu
LEFT JOIN Users u ON tu.UserId = u.Id
LEFT JOIN PostEngagement pe ON tu.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pe.PostId)
GROUP BY
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.BadgeCount,
    tu.AvgDaysSinceCreation,
    tu.RecentComments,
    tu.TotalPostScore,
    tu.AvgPostViewCount,
    tu.TotalUpVotesReceived,
    tu.TotalDownVotesReceived,
    tu.ClosedPostCount,
    u.Location,
    u.WebsiteUrl
HAVING tu.TotalPostScore IS NOT NULL
ORDER BY tu.Rank;