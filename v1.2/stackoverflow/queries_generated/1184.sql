-- {"query": "1184.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1456} 
with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class

    union all

    select
        UserId,
        DisplayName,
        null as Class,
        0 as BadgeCount
    from Users
    where Id not in (select UserId from Badges)
),

RecentQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.AcceptedAnswerId,
        row_number() over(partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId = 1 -- questions only
),

TopAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        row_number() over(partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rank_per_question
    from Posts a
    where a.PostTypeId = 2 -- answers only
),

QuestionVoteStats as (
    select
        p.Id as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 1 then 1 else 0 end) as AcceptedCount
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id
),

TagAggregates as (
    select
        lower(trim(tag)) as Tag,
        count(distinct p.Id) as QuestionsCount,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews,
        max(p.Score) as MaxScore
    from Posts p,
    unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag
    where p.PostTypeId = 1
    group by 1
    having count(distinct p.Id) > 100
),

UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),

ClosedQuestionsWithReason as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as ClosedOn
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10 -- post closed events
),

UserLastSeenRanks as (
    select 
        Id as UserId,
        DisplayName,
        LastAccessDate,
        rank() over (order by LastAccessDate desc nulls last) as LastSeenRank
    from Users
    where LastAccessDate is not null
)

select distinct
    rq.QuestionId,
    rq.Title,
    coalesce(u.DisplayName, rq.OwnerDisplayName) as Author,
    rq.CreationDate,
    coalesce(qvs.UpVotes,0) as UpVotes,
    coalesce(qvs.DownVotes,0) as DownVotes,
    coalesce(qvs.AcceptedCount,0) as AcceptedAnswers,
    ta.AnswerId as TopAnswerId,
    ta.Score as TopAnswerScore,
    ta.CreationDate as TopAnswerCreationDate,
    cb.CloseReasonName,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ta.rank_per_question as AnswerRank,
    u.Reputation,
    coalesce(tagagg.AvgScore,0) as TagAverageScore,
    tagagg.TotalViews as TagTotalViews,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.UpVotesCast,
    ua.DownVotesCast,
    ulr.LastSeenRank,
    concat('Tags: ', coalesce(rq.Tags, '<none>')) as TagString,
    case 
        when rq.AcceptedAnswerId is not null then 'Accepted'
        when cb.PostId is not null then 'Closed'
        else 'Open'
    end as QuestionStatus,
    case 
        when rq.Score > 100 then 'Hot'
        when rq.Score between 50 and 100 then 'Trending'
        else 'Normal'
    end as PopularityCategory
from RecentQuestions rq
left join Users u on u.Id = rq.OwnerUserId
left join TopAnswers ta on ta.QuestionId = rq.QuestionId and ta.rank_per_question = 1
left join QuestionVoteStats qvs on qvs.QuestionId = rq.QuestionId
left join ClosedQuestionsWithReason cb on cb.PostId = rq.QuestionId
left join UserActivity ua on ua.UserId = rq.OwnerUserId
left join TagAggregates tagagg on tagagg.Tag = any(string_to_array(substring(rq.Tags from 2 for char_length(rq.Tags)-2), '><'))
left join UserLastSeenRanks ulr on ulr.UserId = rq.OwnerUserId
where rq.rn <= 10
  and (rq.Score + coalesce(qvs.UpVotes,0) - coalesce(qvs.DownVotes,0)) > 20
order by rq.CreationDate desc, UpVotes desc, TopAnswerScore desc
limit 50;