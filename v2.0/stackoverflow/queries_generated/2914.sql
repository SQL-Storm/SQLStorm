-- {"query": "2914.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1781} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        p.OwnerUserId,
        u.Reputation,
        u.DisplayName,
        row_number() over (partition by t.Id order by coalesce(p.ViewCount, 0) desc) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join Users u on u.Id = p.OwnerUserId
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
TopTagsAnswers as (
    select 
        rtc.TagId,
        rtc.TagName,
        avg(rtc.ViewCount) as AvgQuestionViews,
        avg(rtc.AnswerCount) as AvgAnswerCount,
        count(distinct rtc.OwnerUserId) as DistinctQuestionAskers,
        sum(coalesce(pc.AnswerScore,0)) as TotalAnswerScores,
        sum(case when pc.CommentCount > 2 then 1 else 0 end) as HighlyCommentedAnswers
    from RecursiveTagCounts rtc
    left join (
        select p.ParentId, p.Score as AnswerScore, p.CommentCount
        from Posts p
        where p.PostTypeId = 2
    ) pc on pc.ParentId in (
        select Id from Posts where Tags like '%' || '<' || rtc.TagName || '>' || '%'
    )
    where rtc.rn = 1
    group by rtc.TagId, rtc.TagName
),
UserPostRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank,
        avg(p.Score) over (partition by u.Id) as AvgUserScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
),
CorrelatedMaxVotes as (
    select
        v.PostId,
        max(v.CreationDate) as LastVoteDate,
        count(*) as VotesCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
    from Votes v
    group by v.PostId
),
PostCommentsWithUserInfo as (
    select
        c.Id,
        c.PostId,
        c.Score as CommentScore,
        c.Text as CommentText,
        c.CreationDate,
        u.DisplayName as CommenterName,
        u.Reputation as CommenterReputation,
        c.UserId,
        case when c.UserId is null then 1 else 0 end as IsAnonymousComment
    from Comments c
    left join Users u on u.Id = c.UserId
),
FinalAnalysis as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        pt.Name as PostTypeName,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ta.AvgQuestionViews,
        ta.AvgAnswerCount,
        ta.DistinctQuestionAskers,
        ta.TotalAnswerScores,
        ta.HighlyCommentedAnswers,
        csr.LastVoteDate,
        csr.UpVotes,
        csr.DownVotes,
        csr.Favorites,
        (select count(*) from PostHistory ph where ph.PostId = p.Id and ph.PostHistoryTypeId in (10, 12)) as CloseOrDeletedCount,
        max(case when ph.PostHistoryTypeId = 10 then 'Closed' else null end) as LastClosedStatus,
        max(case when ph.PostHistoryTypeId = 12 then 'Deleted' else null end) as LastDeletedStatus,
        row_number() over (partition by u.Id order by p.Score desc) as UserBestPostRank,
        count(distinct c.Id) as TotalComments,
        sum(case when c.CommentScore > 5 then 1 else 0 end) as HighlyRatedComments,
        string_agg(distinct coalesce(cws.CommenterName, 'Anonymous') || ' [' || coalesce(cws.CommenterReputation::text, '0') || ']', ', ') as CommentersSummary
    from Posts p
    inner join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join TopTagsAnswers ta on ta.TagName = substring(p.Tags from '<([^>]+)>')
    left join CorrelatedMaxVotes csr on csr.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id
    left join PostCommentsWithUserInfo c on c.PostId = p.Id
    left join lateral (
        select * from PostCommentsWithUserInfo cws where cws.PostId = p.Id order by cws.CreationDate desc limit 3
    ) cws on true
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '2 years'
    group by p.Id, pt.Name, u.Id, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, 
             ta.AvgQuestionViews, ta.AvgAnswerCount, ta.DistinctQuestionAskers, ta.TotalAnswerScores, ta.HighlyCommentedAnswers,
             csr.LastVoteDate, csr.UpVotes, csr.DownVotes, csr.Favorites
    having count(distinct c.Id) > 0 or p.Score > 10
)
select
    f.QuestionId,
    f.Title,
    f.CreationDate,
    f.QuestionScore,
    f.ViewCount,
    f.AnswerCount,
    f.FavoriteCount,
    f.PostTypeName,
    f.OwnerName,
    f.OwnerReputation,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.AvgQuestionViews,
    f.AvgAnswerCount,
    f.DistinctQuestionAskers,
    f.TotalAnswerScores,
    f.HighlyCommentedAnswers,
    f.LastVoteDate,
    f.UpVotes,
    f.DownVotes,
    f.Favorites,
    f.CloseOrDeletedCount,
    f.LastClosedStatus,
    f.LastDeletedStatus,
    f.UserBestPostRank,
    f.TotalComments,
    f.HighlyRatedComments,
    left(f.CommentersSummary, 200) as CommentersSummaryTruncated,
    case 
        when f.UpVotes > f.DownVotes then 'Positive'
        when f.UpVotes = f.DownVotes then 'Neutral'
        else 'Negative'
    end as Sentiment,
    case 
        when f.ViewCount > 10000 and f.AnswerCount > 5 and f.FavoriteCount > 100 then 'Hot Topic'
        else 'Regular'
    end as TopicCategory,
    concat_ws(' - ', 
        coalesce(f.OwnerName, 'Unknown User'), 
        'Reputation: ', coalesce(f.OwnerReputation::text, '0'),
        'Badges [G/S/B]: ', coalesce(f.GoldBadges::text, '0'), '/', coalesce(f.SilverBadges::text, '0'), '/', coalesce(f.BronzeBadges::text, '0')
    ) as OwnerSummary
from FinalAnalysis f
order by f.QuestionScore desc nulls last, f.ViewCount desc nulls last
limit 50;