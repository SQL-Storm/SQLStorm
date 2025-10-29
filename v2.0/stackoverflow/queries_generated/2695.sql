-- {"query": "2695.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1074} 
with recursive TagHierarchy as (
    select
        t.Id,
        t.TagName,
        array[t.TagName] as TagPath,
        1 as depth
    from Tags t
    where not exists (
        select 1 from PostLinks pl
        join Posts p on p.Id = pl.PostId
        where pl.RelatedPostId = t.ExcerptPostId
    )
    union all
    select
        t.Id,
        t.TagName,
        th.TagPath || t.TagName,
        th.depth + 1
    from Tags t
    join Posts p on p.ExcerptPostId = t.Id
    join TagHierarchy th on p.Id = th.Id
    where not t.TagName = any(th.TagPath)
),
UserBadgeRanks as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        count(*) over (partition by b.UserId, b.Class order by min(b.Date) rows between unbounded preceding and current row) as BadgeRank,
        row_number() over (partition by b.UserId order by b.Class, min(b.Date)) as BadgeSeq,
        min(b.Date) as FirstAwarded
    from Badges b
    group by b.UserId, b.Name, b.Class
),
PopularQuestionAnswers as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        u.DisplayName as AnswererName,
        u.Reputation as AnswererReputation,
        array(select unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><'))) as TagList,
        (
            select count(*) 
            from Votes v 
            where v.PostId = a.Id and v.VoteTypeId = 2 -- upvotes
        ) as AnswerUpVotes,
        (
            select count(*)
            from Comments c
            where c.PostId = a.Id and c.Score > 0
        ) as PositiveCommentCount,
        case 
            when a.Score > 10 and u.Reputation > 10000 then 'High'
            when a.Score > 5 then 'Medium'
            else 'Low'
        end as AnswerQualityBucket
    from Posts p
    inner join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where p.PostTypeId = 1
    and p.Score > 5
    and p.ClosedDate is null
),
FilteredAnswers as (
    select *
    from PopularQuestionAnswers
    where 
    exists (
        select 1
        from Votes v2 
        where v2.PostId = PopularQuestionAnswers.QuestionId 
        and v2.VoteTypeId = 10 -- Deletion votes in Votes table
        and v2.CreationDate > PopularQuestionAnswers.QuestionCreation
    ) = false
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges,
        max(b.Date) as LastBadgeAwardDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
AnswerRanking as (
    select 
        fa.*, 
        row_number() over (partition by fa.QuestionId order by fa.AnswerScore desc, fa.AnswerUpVotes desc) as AnswerRank
    from FilteredAnswers fa
),
FinalResults as (
    select
        ar.QuestionId,
        ar.Title,
        ar.AnswerId,
        ar.AnswererName,
        ar.AnswererReputation,
        ar.AnswerScore,
        ar.AnswerUpVotes,
        ar.PositiveCommentCount,
        ar.AnswerQualityBucket,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LastBadgeAwardDate,
        jsonb_build_object(
            'QuestionTags', ar.TagList,
            'AcceptedAnswer', (select AcceptedAnswerId from Posts p where p.Id = ar.QuestionId)
        ) as MetaData,
        count(distinct c.Id) over (partition by ar.AnswerId) as CommentCountOnAnswer
    from AnswerRanking ar
    left join UserBadgeSummary ubs on ubs.UserId = (select OwnerUserId from Posts where Id = ar.AnswerId)
    left join Comments c on c.PostId = ar.AnswerId
    where ar.AnswerRank <= 3
)
select * 
from FinalResults
order by AnswerScore desc nulls last, AnswerUpVotes desc nulls last
limit 50;