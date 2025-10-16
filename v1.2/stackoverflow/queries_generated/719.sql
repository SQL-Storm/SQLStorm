-- {"query": "719.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1458} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        p.Level + 1,
        p.Path || child.TagName
    from Tags child
    join RecursiveTagHierarchy p on child.Count < p.Count and child.IsModeratorOnly = 0
    where not child.TagName = any(p.Path)
)
, UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        row_number() over (order by count(b.Id) desc) as UserRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
)
, PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        coalesce(p.Tags,'') as Tags,
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank
    from Posts p
    left join PostTypes pt on p.PostTypeId = pt.Id
    left join Users u on p.OwnerUserId = u.Id
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, u.DisplayName, p.Score, p.ViewCount, p.CreationDate, p.Title, p.Tags, p.AcceptedAnswerId
)
, TopQuestionsWithAnswers as (
    select
        q.PostId as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwnerId,
        q.OwnerName as QuestionOwnerName,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CreationDate as QuestionCreation,
        a.PostId as AnswerId,
        a.OwnerUserId as AnswerOwnerId,
        a.OwnerName as AnswerOwnerName,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        a.CommentCount as AnswerComments,
        a.UpVotes as AnswerUpVotes,
        a.DownVotes as AnswerDownVotes,
        row_number() over (partition by q.PostId order by a.Score desc) as AnswerRank
    from PostStats q
    left join PostStats a on a.ParentId = q.PostId and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
)
select
    tq.QuestionId,
    tq.QuestionTitle,
    tq.QuestionOwnerName,
    tq.QuestionScore,
    tq.QuestionViews,
    date_part('year', age(now(), tq.QuestionCreation)) as YearsSinceAsked,
    tq.AnswerId,
    tq.AnswerOwnerName,
    tq.AnswerScore,
    tq.AnswerComments,
    tq.AnswerUpVotes,
    tq.AnswerDownVotes,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    case when tq.AnswerScore > 0 then round((tq.AnswerUpVotes::numeric / nullif(tq.AnswerScore,0)),2) else null end as UpvoteRatio,
    case when tq.AnswerComments > 0 then round((tq.AnswerComments::numeric / nullif(tq.AnswerScore,0)),2) else 0 end as CommentsPerScore,
    string_agg(distinct rth.TagName, ',' order by rth.Level) filter (where rth.TagName is not null) as RelatedTagsPath
from TopQuestionsWithAnswers tq
left join UserBadgeCounts ub on ub.UserId = tq.AnswerOwnerId
left join LATERAL (
    select distinct unnest(string_to_array(replace(replace(tq.QuestionTitle, '<', ''), '>', ''), ' ')) as TagName
) qtags on true
left join RecursiveTagHierarchy rth on rth.TagName = qtags.TagName
where tq.AnswerRank <= 3
group by 
    tq.QuestionId,
    tq.QuestionTitle,
    tq.QuestionOwnerName,
    tq.QuestionScore,
    tq.QuestionViews,
    tq.QuestionCreation,
    tq.AnswerId,
    tq.AnswerOwnerName,
    tq.AnswerScore,
    tq.AnswerComments,
    tq.AnswerUpVotes,
    tq.AnswerDownVotes,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges
union
select
    p.Id as QuestionId,
    p.Title as QuestionTitle,
    u.DisplayName as QuestionOwnerName,
    p.Score as QuestionScore,
    p.ViewCount as QuestionViews,
    date_part('year', age(now(), p.CreationDate)) as YearsSinceAsked,
    null as AnswerId,
    null as AnswerOwnerName,
    null as AnswerScore,
    null as AnswerComments,
    null as AnswerUpVotes,
    null as AnswerDownVotes,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TagBasedBadges,
    null as UpvoteRatio,
    null as CommentsPerScore,
    null as RelatedTagsPath
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1 and not exists (
    select 1 from Posts a where a.ParentId = p.Id and a.PostTypeId = 2
)
order by QuestionScore desc nulls last, QuestionViews desc nulls last, YearsSinceAsked desc
limit 100;