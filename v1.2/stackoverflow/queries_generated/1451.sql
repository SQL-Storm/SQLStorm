-- {"query": "1451.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1547} 
with RecursivePostForest as (
    -- get top 5 questions with highest view count posted within last 2 years
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, 
           1 as Depth, array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 
      and p.CreationDate > now() - interval '2 years'
    order by p.ViewCount desc 
    limit 5

    union all

    -- recursive part: get answers for each question and answers recursively as if threaded
    select a.Id, coalesce(a.Title, '') as Title, a.OwnerUserId, a.CreationDate, a.Score, a.ViewCount,
           rpf.Depth + 1,
           rpf.Path || a.Id
    from Posts a
    join RecursivePostForest rpf on a.ParentId = rpf.Id
    where a.PostTypeId = 2
      and array_position(rpf.Path, a.Id) is null -- avoid cycles
), 

UserBadgeCount as (
    select b.UserId,
           count(*) keep (dense_rank last order by b.Class) as MaxBadgeClass,
           count(*) as TotalBadges,
           sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges,
           string_agg(distinct b.Name, ';' order by b.Name) as AllBadges
    from Badges b
    group by b.UserId
),

VotesAggregated as (
    select v.PostId,
           sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
           sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
           sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),

PostHistoryChanges as (
    select ph.PostId,
           max(case when pht.Name = 'Post Closed' then ph.CreationDate end) as LastClosedDate,
           max(case when pht.Name = 'Post Reopened' then ph.CreationDate end) as LastReopenedDate,
           count(case when pht.Name = 'Suggested Edit Applied' then 1 else null end) as NumberOfEdits,
           bool_or(ph.UserId is null) as AnyEditsByAnonymous
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    group by ph.PostId
),

RankedComments as (
    select c.Id, c.PostId, c.Text, c.CreationDate, c.UserId,
           row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate asc) as CommentRank
    from Comments c
),

MatchedTagsAndUsers as (
    select distinct p.Id as PostId, u.Id as UserId, u.DisplayName,
           regexp_matches(p.Tags, E'<(.*?)>', 'g') as TagArray
    from Posts p
    join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Tags is not null
),

QuestionWithLinkedDuplicates as (
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount,
           count(pl.Id) filter (where lt.Name = 'Linked') as CrossLinksCount
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
),

CorrelationHighlight as (
    -- correlate tags popularity against user's rep buckets and filter complicated condition for long strings and attribution
    select mt.PostId, count(distinct mt.UserId) as OwnersCount,
      array_length(array_agg(distinct mt.TagArray), 1) as TagCount,
      max(t.Count) as MaxTagCount,
      avg(u.Reputation) as OwnerAvgRep,
      max(length(coalesce(p.Title,''))) as MaxTitleLength
    from MatchedTagsAndUsers mt
    join Posts p on mt.PostId = p.Id
    join Tags t on t.TagName = ANY(mt.TagArray)
    join Users u on mt.UserId = u.Id
    group by mt.PostId
    having max(t.Count) > 50000
       and avg(u.Reputation) > 500
       and max(length(coalesce(p.Title,''))) > 40
),

FinalResult as (
    select 
        rpf.Id as PostId, rpf.Title,
        rpf.OwnerUserId, u.DisplayName as OwnerName,
        rpf.Depth,
        rpf.CreationDate,
        rpf.Score, rpf.ViewCount,
        ubc.MaxBadgeClass,
        ubc.TotalBadges,
        ubc.TagBadges,
        vg.UpVotes,
        vg.DownVotes,
        vg.FavoriteVotes,
        phc.LastClosedDate,
        phc.LastReopenedDate,
        phc.NumberOfEdits,
        phc.AnyEditsByAnonymous,
        qld.DuplicateLinksCount,
        qld.CrossLinksCount,
        corr.OwnersCount,
        corr.TagCount,
        corr.MaxTagCount,
        corr.OwnerAvgRep,
        corr.MaxTitleLength,
        rc.Text as TopCommentText,
        rc.CreationDate as TopCommentCreated
    from RecursivePostForest rpf 
    left join Users u on rpf.OwnerUserId = u.Id
    left join UserBadgeCount ubc on rpf.OwnerUserId = ubc.UserId
    left join VotesAggregated vg on rpf.Id = vg.PostId
    left join PostHistoryChanges phc on rpf.Id = phc.PostId
    left join QuestionWithLinkedDuplicates qld on rpf.Id = qld.Id
    left join CorrelationHighlight corr on rpf.Id = corr.PostId
    left join RankedComments rc 
       on rc.PostId = rpf.Id and rc.CommentRank = 1
    where rpf.Depth <= 3
)

select *,
    case 
      when (Scoreispiece:52->0<> 0 and ViewCount > 100000) then 'High Impact Post'
      when (DuplicateLinksCount > 0 and Depth = 1) then 'Primary Question with Duplicates'
      when (NumberOfEdits > 5 and AnyEditsByAnonymous) then 'Highly Edited by Anons'
      when (MaxBadgeClass = 1 and OwnerAvgRep > 10000) then 'Highly Recognized Owner'
      else 
         concat('Standard Post:score=', Score::text, ' views=', ViewCount::text)
    end as PostCategory,
    substring(coalesce(TopCommentText,'### No Top Comment ###'),1,80) as TopCommentPreview
from FinalResult
order by Depth, ViewCount desc, Score desc
limit 100;