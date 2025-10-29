with recursive RecursiveTags(tagname, depth) as (
    select distinct unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tagname, 1
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    union all
    select rt.tagname, rt.depth + 1
    from RecursiveTags rt
    join Tags t on rt.tagname = t.TagName
    where rt.depth < 2
), 
UserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        array_agg(distinct t.tag) as TagsList,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag
    ) t
    where p.PostTypeId = 1 and p.Score > 0 and p.Tags is not null
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedExists,
        string_agg(distinct u.DisplayName, ', ') as AnswererNames
    from Posts a
    join Posts q on q.Id = a.ParentId
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
    group by a.ParentId, q.AcceptedAnswerId
),
LastEditInfo as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        string_agg(distinct ph.UserDisplayName, ', ') filter (where ph.UserDisplayName is not null) as Editors
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6,7,8,9,14)
    group by ph.PostId
),
VotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
KeywordQuestions as (
    select p.Id
    from Posts p
    where p.PostTypeId = 1 and lower(p.Title) like '%sql%' and p.Score > 5
),
DuplicatePairs as (
    select distinct pl.PostId as DuplicateId, pl.RelatedPostId as OriginalId
    from PostLinks pl
    where pl.LinkTypeId = 3
),
CombinedQuestions as (
    select 
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.TagsList,
        ans.AnswerCount,
        ans.AvgAnswerScore,
        ans.AcceptedExists,
        ans.AnswererNames,
        le.LastEditDate,
        le.Editors,
        vs.UpVotes, vs.DownVotes, vs.FavoriteVotes, vs.CloseVotes,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
        case when dq.DuplicateId is not null then dq.OriginalId else null end as DuplicateOf,
        case 
            when exists (select 1 from KeywordQuestions kq where kq.Id = tq.Id) then true 
            else false 
        end as ContainsSQLKeyword
    from TopQuestions tq
    left join AnswerStats ans on ans.QuestionId = tq.Id
    left join LastEditInfo le on le.PostId = tq.Id
    left join VotesSummary vs on vs.PostId = tq.Id
    left join UserBadges ub on ub.UserId = tq.OwnerUserId
    left join DuplicatePairs dq on dq.DuplicateId = tq.Id
)
select 
    Id,
    left(Title, 100) as ShortTitle,
    OwnerUserId,
    Score,
    ViewCount,
    coalesce(AnswerCount, 0) as AnswerCount,
    coalesce(round(CAST(AvgAnswerScore AS numeric),2), 0) as AverageAnswerScore,
    AcceptedExists,
    coalesce(AnswererNames, 'No answers') as AnswererNames,
    LastEditDate,
    coalesce(Editors, 'No editors') as Editors,
    UpVotes,
    DownVotes,
    FavoriteVotes,
    CloseVotes,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    DuplicateOf,
    ContainsSQLKeyword,
    array_to_string(TagsList, ', ') as Tags
from CombinedQuestions
where 
    (Score > 10 and ViewCount > 1000) 
    or ContainsSQLKeyword = true
order by Score desc, ViewCount desc
limit 100;