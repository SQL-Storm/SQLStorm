-- {"query": "2592.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2249} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class as BadgeClass,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Class
    union all
    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        case when r.BadgeClass is null then 3 else r.BadgeClass end as BadgeClass,
        r.BadgeCount
    from RecursiveUserBadgeCounts r
    where r.BadgeClass is null
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        regex_split_to_table(coalesce(p.Tags, ''), E'<([^>]+)>') as Tag -- split tags into lines
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
      and p.Score >= 0
      and p.ViewCount > 10
),
AnswerRanks as (
    select
        f.PostTypeId,
        f.Id as PostId,
        f.OwnerUserId,
        f.ParentId,
        f.CreationDate,
        f.Score,
        f.ViewCount,
        f.Tag,
        row_number() over (partition by f.ParentId order by f.Score desc, f.CreationDate asc) as AnswerRank
    from FilteredPosts f
    where f.PostTypeId = 2
),
TopAnswersWithParent as (
    select
        a.PostId,
        a.OwnerUserId as AnswerOwnerId,
        a.ParentId as QuestionId,
        q.OwnerUserId as QuestionOwnerId,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        a.CreationDate as AnswerCreation,
        q.CreationDate as QuestionCreation,
        a.ViewCount as AnswerViewCount,
        q.ViewCount as QuestionViewCount,
        a.Tag as CommonTag
    from AnswerRanks a
    join FilteredPosts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.AnswerRank <= 3
),
UserReputationChanges as (
    select
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        row_number() over (partition by ph.UserId order by ph.CreationDate desc) as rn,
        max(ph.CreationDate) over (partition by ph.UserId) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- edits to title, body, tags
),
UserBadgesAggregated as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserBadgesRanked as (
    select
        *,
        rank() over (order by GoldBadges desc, SilverBadges desc, BronzeBadges desc, DisplayName asc) as BadgeRank
    from UserBadgesAggregated
),
TaggedQuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        coalesce(link.DuplicateCount, 0) as DuplicateCount,
        q.Tags,
        -- Extract tags into array
        string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><') as TagArray
    from Posts q
    left join (
        select
            pl.PostId,
            count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount
        from PostLinks pl
        join LinkTypes lt on lt.Id = pl.LinkTypeId
        group by pl.PostId
    ) link on link.PostId = q.Id
    where q.PostTypeId = 1
      and q.Score > 0
      and q.DuplicateCount > 0
),
DistinctUsersQuestionsAnswers as (
    select distinct
        u.Id as UserId,
        u.DisplayName,
        pq.QuestionId,
        pq.Title,
        pq.QuestionScore,
        pq.DuplicateCount,
        pq.TagArray,
        t.BadgeRank
    from Users u
    join TaggedQuestionsWithDuplicates pq on pq.OwnerUserId = u.Id
    join UserBadgesRanked t on t.UserId = u.Id
),
EnrichedPostsWithVotes as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        case 
            when p.ClosedDate is not null then 1 else 0 
        end as IsClosed
    from Posts p
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
)
select 
    euq.UserId,
    euq.DisplayName,
    euq.Title,
    euq.QuestionScore,
    euq.DuplicateCount,
    euq.BadgeRank,
    ep.PostId,
    ep.PostTypeId,
    ep.Score as AnswerScore,
    ep.UpVotes,
    ep.DownVotes,
    ep.ViewCount,
    ep.HasAcceptedAnswer,
    ep.IsClosed,
    ts.Tag as FocusTag,
    phc.PostHistoryTypeId,
    phc.CreationDate as LastEditDate,
    case when ep.Score > 10 and ep.UpVotes > 50 then 'HighImpact' else 'Normal' end as PostImpact,
    concat(
        euq.Title, ' [tags: ',
        array_to_string(array(
            select distinct t from unnest(euq.TagArray) as t order by t
        ), ', '), ']'
    ) as TitleWithTags,
    rank() over (partition by euq.UserId order by ep.Score desc) as AnswerRankPerUser
from DistinctUsersQuestionsAnswers euq
join EnrichedPostsWithVotes ep on ep.OwnerUserId = euq.UserId and ep.PostTypeId = 2
left join TaggedQuestionsWithDuplicates ts on ts.QuestionId = ep.Id
left join Lateral (
    select ph.PostHistoryTypeId, ph.CreationDate
    from PostHistory ph
    where ph.UserId = euq.UserId
      and ph.PostId = ep.PostId
    order by ph.CreationDate desc
    limit 1
) phc on true
where ep.Score > 5
  and (ep.IsClosed = 0 or ep.IsClosed is null)
union
select 
    u.Id as UserId,
    u.DisplayName,
    p.Title,
    p.Score as QuestionScore,
    0 as DuplicateCount,
    9999 as BadgeRank,
    null as PostId,
    null as PostTypeId,
    null as AnswerScore,
    null as UpVotes,
    null as DownVotes,
    null as ViewCount,
    null as HasAcceptedAnswer,
    null as IsClosed,
    null as FocusTag,
    null as PostHistoryTypeId,
    null as LastEditDate,
    null as PostImpact,
    concat(
        p.Title, ' [tags: ',
        coalesce(array_to_string(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), ', '), '')
        ,']') as TitleWithTags,
    null as AnswerRankPerUser
from Posts p
join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.Score > 100
except
select 
    euq.UserId,
    euq.DisplayName,
    euq.Title,
    euq.QuestionScore,
    euq.DuplicateCount,
    euq.BadgeRank,
    ep.PostId,
    ep.PostTypeId,
    ep.Score as AnswerScore,
    ep.UpVotes,
    ep.DownVotes,
    ep.ViewCount,
    ep.HasAcceptedAnswer,
    ep.IsClosed,
    ts.Tag as FocusTag,
    phc.PostHistoryTypeId,
    phc.CreationDate as LastEditDate,
    case when ep.Score > 10 and ep.UpVotes > 50 then 'HighImpact' else 'Normal' end as PostImpact,
    concat(
        euq.Title, ' [tags: ',
        array_to_string(array(
            select distinct t from unnest(euq.TagArray) as t order by t
        ), ', '), ']'
    ) as TitleWithTags,
    rank() over (partition by euq.UserId order by ep.Score desc) as AnswerRankPerUser
from DistinctUsersQuestionsAnswers euq
join EnrichedPostsWithVotes ep on ep.OwnerUserId = euq.UserId and ep.PostTypeId = 2
left join TaggedQuestionsWithDuplicates ts on ts.QuestionId = ep.Id
left join Lateral (
    select ph.PostHistoryTypeId, ph.CreationDate
    from PostHistory ph
    where ph.UserId = euq.UserId
      and ph.PostId = ep.PostId
    order by ph.CreationDate desc
    limit 1
) phc on true
where ep.Score > 5
  and (ep.IsClosed = 0 or ep.IsClosed is null)
order by BadgeRank, UserId, AnswerRankPerUser nulls last
limit 100;