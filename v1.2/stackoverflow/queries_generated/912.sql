-- {"query": "912.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1517} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, 0 as Level, array[t.TagName] as Ancestors
    from Tags t
    where t.IsRequired = 1
    union all
    select c.Id, c.TagName, c.Count, r.Level + 1, r.Ancestors || c.TagName
    from Tags c
    join RecursiveTagHierarchy r on c.ExcerptPostId = r.WikiPostId
    where c.Id <> all(r.Ancestors)
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as TotalBadges,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeNames,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVoteAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as TotalBountyClosed
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title
),
RankedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
QuestionsWithTopAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        r.Id as TopAnswerId,
        r.Score as TopAnswerScore,
        r.CreationDate as TopAnswerCreation,
        u.DisplayName as QuestionOwner,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        pva.UpVotes,
        pva.DownVotes,
        pva.TotalBountyStarted,
        pva.TotalBountyClosed
    from Posts q
    left join RankedAnswers r on r.ParentId = q.Id and r.AnswerRank = 1
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeStats ub on ub.UserId = q.OwnerUserId
    left join PostVoteAggregates pva on pva.Id = q.Id
    where q.PostTypeId = 1
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as CloseEventRank
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) filter (where ph.PostHistoryTypeId = 10)
    where ph.PostHistoryTypeId = 10
),
FinalClosedQuestions as (
    select cq.QuestionId, cq.Title, cq.TopAnswerId, cq.TopAnswerScore, cq.TopAnswerCreation, cq.QuestionOwner,
           cq.GoldBadges, cq.SilverBadges, cq.BronzeBadges, cq.UpVotes, cq.DownVotes,
           cq.TotalBountyStarted, cq.TotalBountyClosed, cc.CloseReason, cc.CloseDate
    from QuestionsWithTopAnswers cq
    left join ClosedQuestionsWithReasons cc on cc.PostId = cq.QuestionId and cc.CloseEventRank = 1
    where cc.PostId is not null
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as PostsLastYear,
        count(distinct c.Id) over (partition by u.Id order by c.CreationDate rows between 365 preceding and current row) as CommentsLastYear,
        sum(case when p.Score > 0 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as PositiveScorePostsLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
),
TopTagsQuestionCount as (
    select
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) as Tag,
        count(q.Id) as QuestionCount
    from Posts q
    where q.PostTypeId = 1
    group by Tag
    order by QuestionCount desc
    limit 10
)
select
    fcq.QuestionId,
    fcq.Title,
    fcq.CloseReason,
    fcq.CloseDate,
    fcq.TopAnswerId,
    fcq.TopAnswerScore,
    fcq.TopAnswerCreation,
    concat_ws(' | ', fcq.QuestionOwner, 'Gold:', fcq.GoldBadges::text, 'Silver:', fcq.SilverBadges::text, 'Bronze:', fcq.BronzeBadges::text) as OwnerBadgeSummary,
    fcq.UpVotes,
    fcq.DownVotes,
    fcq.TotalBountyStarted,
    fcq.TotalBountyClosed,
    ua.PostsLastYear,
    ua.CommentsLastYear,
    ua.PositiveScorePostsLastYear,
    (select string_agg(Tag || ':' || QuestionCount::text, ', ') from TopTagsQuestionCount) as TopTags,
    case when fcq.TopAnswerScore is null then 'No Answers' else 'Answered' end as AnswerStatus,
    case when fcq.CloseDate is not null and fcq.CloseDate > fcq.TopAnswerCreation then 'Closed After Answer' else 'Closed Before Answer or No Answer' end as CloseTiming
from FinalClosedQuestions fcq
left join UserActivityWindow ua on ua.UserId = (select OwnerUserId from Posts where Id = fcq.QuestionId)
where fcq.GoldBadges > 0 or fcq.UpVotes > 10
order by fcq.CloseDate desc nulls last
limit 100;