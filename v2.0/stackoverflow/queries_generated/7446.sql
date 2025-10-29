-- {"query": "7446.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2469} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownvoteCount,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgScore,
        STRING_AGG(DISTINCT t.TagName, ', ') as Tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        PostCount,
        QuestionCount,
        AnswerCount,
        BadgeCount,
        UpvoteCount,
        DownvoteCount,
        LastPostDate,
        AvgScore,
        Tags,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) as RankByPostCount,
        DENSE_RANK() OVER (ORDER BY AVG(p.Score) DESC) as RankByAvgScore
    FROM UserStats us
    LEFT JOIN Posts p ON us.UserId = p.OwnerUserId
    WHERE p.CreationDate >= '2022-01-01'
),
QuestionAnalysis AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        STRING_AGG(DISTINCT CASE WHEN a.Score > 0 THEN a.OwnerUserId END, ', ') as PositiveAnswerAuthors,
        COUNT(DISTINCT a.Id) as TotalAnswerCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as MaxAnswerScore,
        MIN(a.CreationDate) as FirstAnswerDate,
        MAX(a.CreationDate) as LastAnswerDate,
        COUNT(DISTINCT CASE WHEN a.OwnerUserId IS NOT NULL THEN a.OwnerUserId END) as AnswerAuthorCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) as CommentCountOnQuestion,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) as UpvoteCountOnQuestion,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) as DownvoteCountOnQuestion,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as HistoryActionCount
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.ViewCount > 1000
        AND q.CreationDate >= '2022-01-01'
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.CreationDate, q.OwnerUserId, q.Tags
),
DetailedUserAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.BadgeCount,
        tu.UpvoteCount,
        tu.DownvoteCount,
        tu.LastPostDate,
        ROUND(tu.AvgScore, 2) as AvgScore,
        tu.Tags,
        tu.RankByReputation,
        tu.RankByPostCount,
        tu.RankByAvgScore,
        CASE WHEN tu.RankByReputation <= 10 THEN 'Top 10 Reputation' 
             WHEN tu.RankByPostCount <= 20 THEN 'Top 20 Post Count' 
             ELSE 'Other' END as UserTier,
        (CASE 
            WHEN tu.Reputation >= 100000 THEN 'Legend'
            WHEN tu.Reputation >= 50000 THEN 'Master'
            WHEN tu.Reputation >= 10000 THEN 'Expert'
            WHEN tu.Reputation >= 1000 THEN 'Beginner'
            ELSE 'Newbie'
        END) as RepLevel,
        (CASE 
            WHEN tu.PostCount >= 100 THEN 'Elite'
            WHEN tu.PostCount >= 50 THEN 'Veteran'
            WHEN tu.PostCount >= 10 THEN 'Enthusiast'
            ELSE 'Newbie'
        END) as PostLevel,
        (tu.UpvoteCount - tu.DownvoteCount) as NetVotes,
        (tu.UpvoteCount * 1.0 / NULLIF(tu.UpvoteCount + tu.DownvoteCount, 0)) as UpvoteRatio,
        (tu.BadgeCount * 1.0 / NULLIF(tu.PostCount, 0)) as BadgePerPostRatio,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tu.UserId AND v.VoteTypeId = 5) as FavoriteCount,
        STRING_AGG(DISTINCT CASE 
            WHEN v.VoteTypeId IN (2,3) THEN 'Vote' 
            WHEN v.VoteTypeId IN (6,7) THEN 'Close/Open'
            WHEN v.VoteTypeId IN (8,9) THEN 'Bounty'
            ELSE 'Other'
        END, ', ') as VoteTypes
    FROM TopUsers tu
    LEFT JOIN Votes v ON tu.UserId = v.UserId
    WHERE tu.Reputation >= 1000
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.PostCount, tu.QuestionCount, tu.AnswerCount, 
             tu.BadgeCount, tu.UpvoteCount, tu.DownvoteCount, tu.LastPostDate, tu.AvgScore, tu.Tags,
             tu.RankByReputation, tu.RankByPostCount, tu.RankByAvgScore
),
CombinedAnalysis AS (
    SELECT 
        dua.UserId,
        dua.DisplayName,
        dua.Reputation,
        dua.PostCount,
        dua.QuestionCount,
        dua.AnswerCount,
        dua.BadgeCount,
        dua.UpvoteCount,
        dua.DownvoteCount,
        dua.LastPostDate,
        dua.AvgScore,
        dua.Tags,
        dua.RankByReputation,
        dua.RankByPostCount,
        dua.RankByAvgScore,
        dua.UserTier,
        dua.RepLevel,
        dua.PostLevel,
        dua.NetVotes,
        ROUND(dua.UpvoteRatio, 3) as UpvoteRatio,
        ROUND(dua.BadgePerPostRatio, 3) as BadgePerPostRatio,
        dua.FavoriteCount,
        COALESCE(dua.VoteTypes, '') as VoteTypes,
        qa.QuestionId,
        qa.Title,
        qa.Score as QuestionScore,
        qa.ViewCount,
        qa.AnswerCount as QuestionAnswerCount,
        qa.CommentCount as QuestionCommentCount,
        qa.CreationDate as QuestionCreationDate,
        qa.Tags as QuestionTags,
        qa.PositiveAnswerAuthors,
        qa.TotalAnswerCount,
        ROUND(qa.AvgAnswerScore, 2) as AvgAnswerScore,
        qa.MaxAnswerScore,
        qa.FirstAnswerDate,
        qa.LastAnswerDate,
        qa.AnswerAuthorCount,
        qa.CommentCountOnQuestion,
        qa.UpvoteCountOnQuestion,
        qa.DownvoteCountOnQuestion,
        qa.HistoryActionCount,
        CASE 
            WHEN qa.AnswerCount > 0 AND qa.ViewCount > 1000 AND qa.Score > 10 THEN 'High Impact Question'
            WHEN qa.AnswerCount > 0 AND qa.ViewCount > 500 THEN 'Medium Impact Question'
            ELSE 'Low Impact Question'
        END as QuestionCategory,
        ROW_NUMBER() OVER (PARTITION BY dua.UserId ORDER BY qa.ViewCount DESC) as UserQuestionRanking,
        CASE 
            WHEN dua.Reputation > 10000 AND qa.ViewCount > 5000 THEN 'Elite Question'
            WHEN dua.Reputation > 5000 AND qa.ViewCount > 2000 THEN 'Expert Question'
            WHEN dua.Reputation > 1000 AND qa.ViewCount > 500 THEN 'Regular Question'
            ELSE 'Basic Question'
        END as QuestionTier
    FROM DetailedUserAnalysis dua
    LEFT JOIN QuestionAnalysis qa ON dua.UserId = qa.OwnerUserId
    WHERE qa.QuestionId IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.BadgeCount,
    ca.UpvoteCount,
    ca.DownvoteCount,
    ca.LastPostDate,
    ca.AvgScore,
    ca.Tags,
    ca.RankByReputation,
    ca.RankByPostCount,
    ca.RankByAvgScore,
    ca.UserTier,
    ca.RepLevel,
    ca.PostLevel,
    ca.NetVotes,
    ca.UpvoteRatio,
    ca.BadgePerPostRatio,
    ca.FavoriteCount,
    ca.VoteTypes,
    ca.QuestionId,
    ca.Title,
    ca.QuestionScore,
    ca.ViewCount,
    ca.QuestionAnswerCount,
    ca.QuestionCommentCount,
    ca.QuestionCreationDate,
    ca.QuestionTags,
    ca.PositiveAnswerAuthors,
    ca.TotalAnswerCount,
    ca.AvgAnswerScore,
    ca.MaxAnswerScore,
    ca.FirstAnswerDate,
    ca.LastAnswerDate,
    ca.AnswerAuthorCount,
    ca.CommentCountOnQuestion,
    ca.UpvoteCountOnQuestion,
    ca.DownvoteCountOnQuestion,
    ca.HistoryActionCount,
    ca.QuestionCategory,
    ca.UserQuestionRanking,
    ca.QuestionTier,
    (CASE 
        WHEN ca.QuestionScore > 50 AND ca.ViewCount > 1000 AND ca.TotalAnswerCount > 5 THEN 1
        WHEN ca.QuestionScore > 20 AND ca.ViewCount > 500 AND ca.TotalAnswerCount > 2 THEN 1
        ELSE 0
    END) as HighQualityQuestionFlag,
    (SELECT COUNT(DISTINCT ph.Id) 
     FROM PostHistory ph 
     WHERE ph.PostId = ca.QuestionId 
       AND ph.CreationDate BETWEEN '2022-01-01' AND '2023-01-01') as RecentHistoryCount
FROM CombinedAnalysis ca
WHERE ca.Reputation > 1000
  AND ca.ViewCount > 200
  AND ca.QuestionScore >= 0
  AND ca.TotalAnswerCount >= 0
  AND ca.AvgAnswerScore IS NOT NULL
ORDER BY 
    ca.Reputation DESC,
    ca.ViewCount DESC,
    ca.QuestionScore DESC,
    ca.UserQuestionRanking ASC,
    ca.LastPostDate DESC
LIMIT 500;