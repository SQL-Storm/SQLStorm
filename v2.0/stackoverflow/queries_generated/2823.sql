-- {"query": "2823.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1450} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.CreationDate as PostCreation,
        u.Id as OwnerUserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn
    from 
        Tags t
        join Posts p on p.Tags like concat('%<', t.TagName, '>%')
        left join Users u on u.Id = p.OwnerUserId
    where 
        p.PostTypeId = 1
),
TopPostsPerTag as (
    select 
        TagId,
        TagName,
        PostId,
        PostCreation,
        OwnerUserId,
        Reputation
    from RecursiveTagCounts
    where rn <= 3
),
UserBadgeAgg as (
    select 
        b.UserId,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        row_number() over (partition by b.UserId order by max(b.Date) desc) as latest_badge_rank
    from Badges b
    group by b.UserId
),
UserActivityRecent as (
    select 
        u.Id as UserId,
        count(distinct ph.Id) as RecentPostHistoryCount,
        max(ph.CreationDate) as LatestPostHistory,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesCast,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenVotesCast
    from Users u
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate > now() - interval '90 days'
    group by u.Id
),
QualifiedUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ua.RecentPostHistoryCount, 0) as RecentActivityCount,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        ua.CloseVotesCast,
        ua.ReopenVotesCast
    from Users u
    left join UserBadgeAgg ub on ub.UserId = u.Id and ub.latest_badge_rank = 1
    left join UserActivityRecent ua on ua.UserId = u.Id
    where u.Reputation > 1000
),
QuestionWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerDate,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
AnswerStats as (
    select
        QuestionId,
        sum(case when AnswerScore > 0 then 1 else 0 end) as PositiveAnswersCount,
        max(AnswerScore) as MaxAnswerScore,
        min(AnswerScore) as MinAnswerScore
    from QuestionWithAnswers
    group by QuestionId
),
ComplexResults as (
    select distinct
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.ViewCount,
        q.QuestionScore,
        q.QuestionOwner,
        u.DisplayName as QuestionOwnerName,
        u.Reputation as QuestionOwnerReputation,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerOwner,
        ua.DisplayName as AnswerOwnerName,
        ua.Reputation as AnswerOwnerReputation,
        ans.PositiveAnswersCount,
        ans.MaxAnswerScore,
        ans.MinAnswerScore,
        array_to_string(array_agg(distinct nullif(b.Name, '')), ', ') as BadgesOfAnswerOwner,
        (
            select count(*)
            from Votes v
            where v.PostId = q.QuestionId and v.VoteTypeId = 2 -- UpMod
              and v.CreationDate > now() - interval '30 days'
        ) as RecentQuestionUpvotes,
        (
            select count(*)
            from PostLinks pl
            where pl.PostId = q.QuestionId and pl.LinkTypeId = 1
        ) as NumberOfLinkedPosts,
        row_number() over (partition by q.QuestionId order by a.AnswerScore desc nulls last) as AnswerRank
    from QuestionWithAnswers q
    left join QualifiedUsers u on u.Id = q.QuestionOwner
    left join Posts a on a.Id = q.AnswerId
    left join QualifiedUsers ua on ua.Id = a.OwnerUserId
    left join AnswerStats ans on ans.QuestionId = q.QuestionId
    left join Badges b on b.UserId = a.OwnerUserId
    where q.AnswerRank = 1
)
select
    cr.QuestionId,
    cr.Title,
    cr.CreationDate,
    cr.ViewCount,
    cr.QuestionScore,
    cr.QuestionOwner,
    coalesce(cr.QuestionOwnerName, 'Anonymous') as QuestionOwnerName,
    cr.QuestionOwnerReputation,
    cr.AnswerId,
    cr.AnswerScore,
    cr.AnswerOwner,
    coalesce(cr.AnswerOwnerName, 'Anonymous') as AnswerOwnerName,
    cr.AnswerOwnerReputation,
    cr.PositiveAnswersCount,
    cr.MaxAnswerScore,
    cr.MinAnswerScore,
    cr.BadgesOfAnswerOwner,
    cr.RecentQuestionUpvotes,
    cr.NumberOfLinkedPosts,
    case 
        when cr.ViewCount > 10000 and cr.PositiveAnswersCount > 5 then 'Hot Question'
        when cr.ViewCount between 1000 and 10000 then 'Moderate'
        else 'Low Activity'
    end as ActivityCategory,
    length(cr.Title) as TitleLength,
    substring(cr.Title from '^[^a-zA-Z0-9]*([a-zA-Z0-9]+)') as TitleFirstWord,
    coalesce(nullif(cr.BadgesOfAnswerOwner, ''), 'No Badges') as BadgeStatus
from ComplexResults cr
where cr.QuestionScore > 0
order by cr.ViewCount desc nulls last, cr.QuestionScore desc nulls last
limit 50;