-- {"query": "2227.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1804} 
with RecursiveUserTags as (
    select 
        u.Id as UserId,
        unnest(string_to_array(coalesce(p.Tags,''),'><')) as Tag
    from 
        Users u
    join 
        Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    where p.Tags is not null
    union all
    select 
        rut.UserId,
        unnest(string_to_array(t.Tags,'><'))
    from RecursiveUserTags rut
    join Posts p on p.Tags like '%'||rut.Tag||'%'
    join Tags t on t.TagName = rut.Tag
    where rut.Tag is not null
),
UserBadgeTagCounts as (
    select
        b.UserId,
        b.Name as BadgeName,
        count(distinct rut.Tag) as DistinctTags,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    left join RecursiveUserTags rut on rut.UserId = b.UserId
    group by b.UserId, b.Name
),
LatestPostVotes as (
    select distinct on (v.PostId)
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        v.UserId as VoterId,
        v.BountyAmount
    from Votes v
    where v.VoteTypeId in (2,3,8,9)
    order by v.PostId, v.CreationDate desc
),
QuestionAnswerRanks as (
    select 
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank,
        q.AcceptedAnswerId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
PostClosingInfo as (
    select 
        ph.PostId,
        ph.PostHistoryTypeId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
UserReputationWindows as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        sum(coalesce(vtCnt.UpMod,0)) over (order by u.CreationDate rows between unbounded preceding and current row) as CumulativeUpvotes,
        sum(coalesce(vtCnt.DownMod,0)) over (order by u.CreationDate rows between unbounded preceding and current row) as CumulativeDownvotes,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join (
        select UserId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpMod,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownMod
        from Votes
        group by UserId
    ) vtCnt on vtCnt.UserId = u.Id
),
PostAnswerVotes as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        count(distinct case when v.VoteTypeId = 2 then v.Id end) as UpVotes,
        count(distinct case when v.VoteTypeId = 3 then v.Id end) as DownVotes,
        count(distinct v.Id) as TotalVotes
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.ParentId, a.Id
),
ComplexUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct b.Id) as TotalBadges,
        count(distinct c.Id) filter (where c.Score > 0) as PositiveComments,
        max(ph.CreationDate) as LastEditDate,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotesReceived,
        count(distinct distinctTags.Tag) as DistinctTagsOnPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join LATERAL (
        select distinct unnest(string_to_array(coalesce(p2.Tags,''),'><')) as Tag
        from Posts p2
        where p2.OwnerUserId = u.Id and p2.Tags is not null
    ) distinctTags on true
    group by u.Id, u.DisplayName
)
select
    q.Title,
    q.QuestionId,
    q.AnswerId,
    q.AnswerUserId,
    q.AnswerScore,
    q.AnswerRank,
    q.AcceptedAnswerId,
    pci.CloseReason,
    pci.CloseDate,
    urw.DisplayName as QuestionAuthor,
    urw.ReputationRank,
    urw.CumulativeUpvotes,
    urw.CumulativeDownvotes,
    ubtc.DistinctTags,
    ubtc.GoldBadges,
    ubtc.SilverBadges,
    ubtc.BronzeBadges,
    paw.UpVotes,
    paw.DownVotes,
    paw.TotalVotes,
    cua.TotalPosts,
    cua.TotalBadges,
    cua.PositiveComments,
    cua.LastEditDate,
    cua.EditCount,
    cua.UpVotesReceived,
    cua.DownVotesReceived,
    cua.DistinctTagsOnPosts,
    concat_ws(' | ', replace(coalesce(q.Tags,''),'><',',')) as TagList,
    case 
        when q.Score > 100 then 'Hot'
        when q.Score between 50 and 100 then 'Popular'
        else 'Regular'
    end as QuestionPopularity,
    row_number() over (partition by q.AnswerUserId order by q.AnswerScore desc) as AnswererRank,
    case when q.AcceptedAnswerId = q.AnswerId then true else false end as IsAcceptedAnswer,
    (
        select count(*) 
        from Comments c2 
        where c2.PostId = q.QuestionId and c2.CreationDate > q.QuestionCreation
            and (c2.Text ilike '%help%' or c2.Text ilike '%debug%')
    ) as HelpCommentsAfterQuestionCreation
from QuestionAnswerRanks q
left join PostClosingInfo pci on pci.PostId = q.QuestionId
left join UserReputationWindows urw on urw.UserId = (select OwnerUserId from Posts where Id = q.QuestionId)
left join UserBadgeTagCounts ubtc on ubtc.UserId = urw.UserId
left join PostAnswerVotes paw on paw.AnswerId = q.AnswerId
left join ComplexUserActivity cua on cua.UserId = q.AnswerUserId
where coalesce(pci.CloseDate, '2999-12-31') > q.QuestionCreation
  and q.AnswerRank <= 3
union
select 
    null,
    -1,
    null,
    -1,
    -1,
    -1,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null
order by AnswererRank nulls last, QuestionPopularity desc, q.AnswerScore desc
limit 100;