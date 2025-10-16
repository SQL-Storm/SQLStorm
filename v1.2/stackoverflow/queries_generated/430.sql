-- {"query": "430.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1589} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesEarned,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserTopPosts as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostWithAcceptedAnswer as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerUserId,
        a.CreationDate as AcceptedAnswerCreationDate
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
CloseReasonSummary as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    group by ph.PostId, crt.Name
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        coalesce(ubg_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubg_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubg_bronze.BadgeCount,0) as BronzeBadges,
        ru.QuestionsAsked,
        ru.AnswersGiven,
        ru.CommentsMade,
        ru.Reputation,
        ru.CreationDate,
        ru.LastAccessDate
    from Users u
    left join UserBadgeRanks ubg_gold on ubg_gold.UserId = u.Id and ubg_gold.Class = 1
    left join UserBadgeRanks ubg_silver on ubg_silver.UserId = u.Id and ubg_silver.Class = 2
    left join UserBadgeRanks ubg_bronze on ubg_bronze.UserId = u.Id and ubg_bronze.Class = 3
    left join RecursiveUserActivity ru on ru.UserId = u.Id
),
TopQuestionsWithStats as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        pwa.AcceptedAnswerScore,
        pwa.AcceptedAnswerOwnerUserId,
        pwa.AcceptedAnswerCreationDate,
        crs.CloseReasonName,
        crs.CloseCount,
        row_number() over (order by q.Score desc nulls last, q.ViewCount desc nulls last) as RankByScore
    from Posts q
    left join PostWithAcceptedAnswer pwa on pwa.QuestionId = q.Id
    left join CloseReasonSummary crs on crs.PostId = q.Id
    where q.PostTypeId = 1
),
UserTagParticipation as (
    select
        u.Id as UserId,
        t.TagName,
        count(distinct p.Id) as PostsCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as t(TagName)
    group by u.Id, t.TagName
),
RankedUserTagParticipation as (
    select
        utp.UserId,
        utp.TagName,
        utp.PostsCount,
        rank() over (partition by utp.UserId order by utp.PostsCount desc) as TagRank
    from UserTagParticipation utp
),
UserTopTags as (
    select
        UserId,
        TagName,
        PostsCount
    from RankedUserTagParticipation
    where TagRank <= 3
),
FinalUserStats as (
    select
        ua.Id as UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        coalesce(string_agg(distinct utt.TagName || '(' || utt.PostsCount || ')', ', '), 'No Tags') as TopTags,
        case
            when ua.Reputation >= 10000 then 'Expert'
            when ua.Reputation >= 1000 then 'Intermediate'
            else 'Beginner'
        end as ReputationLevel,
        ua.CreationDate,
        ua.LastAccessDate
    from UserAggregates ua
    left join UserTopTags utt on utt.UserId = ua.Id
    group by ua.Id, ua.DisplayName, ua.Reputation, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.CreationDate, ua.LastAccessDate
)
select
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.ReputationLevel,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.QuestionsAsked,
    f.AnswersGiven,
    f.CommentsMade,
    f.TopTags,
    tq.Id as TopQuestionId,
    tq.Title as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViews,
    tq.AnswerCount as TopQuestionAnswerCount,
    tq.FavoriteCount as TopQuestionFavorites,
    coalesce(tq.CloseReasonName, 'Open') as TopQuestionCloseReason,
    tq.CloseCount as TopQuestionCloseVotes,
    tq.AcceptedAnswerScore,
    tq.AcceptedAnswerOwnerUserId,
    tq.AcceptedAnswerCreationDate
from FinalUserStats f
left join TopQuestionsWithStats tq on tq.OwnerUserId = f.UserId and tq.RankByScore = 1
where f.Reputation > 500
order by f.Reputation desc, tq.Score desc nulls last
limit 100;