-- {"query": "1302.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1623} 
with RecursivePosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        0 as Depth,
        cast(p.Id as varchar) as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select
        c.Id,
        c.PostTypeId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.AcceptedAnswerId,
        c.ParentId,
        rp.Depth + 1,
        rp.Path || '->' || cast(c.Id as varchar)
    from Posts c
    inner join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId = 2
), UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by b.UserId order by count(*) desc, b.Class) as rn
    from Badges b
    group by b.UserId, b.Class
), LatestPostHistoryPerPost as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Text,
        ph.Comment
    from PostHistory ph 
    order by ph.PostId, ph.CreationDate desc
), CTE_ExpensiveTags as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Score,
        p.ViewCount,
        p.CreationDate
    from Tags t
    inner join Posts p on p.Id = t.ExcerptPostId
    where t.Count > 5000 and p.PostTypeId = 1
), CTE_PostsWithVotes AS (
    select
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(up.TotalUp,0) as UpVotes,
        coalesce(dn.TotalDown,0) as DownVotes,
        coalesce(fv.FavoriteCount,0) as FavoriteCount
    from Posts p
    left join (
        select v.PostId, count(*) as TotalUp from Votes v where v.VoteTypeId = 2 group by v.PostId
    ) up on up.PostId = p.Id
    left join (
        select v.PostId, count(*) as TotalDown from Votes v where v.VoteTypeId = 3 group by v.PostId
    ) dn on dn.PostId = p.Id
    left join (
        select PostId, count(*) as FavoriteCount from Posts group by PostId -- fake for structure, no Favorites votes after 2022!
    ) fv on fv.PostId = p.Id
), MostCommentedPosts as (
    select
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
    order by CommentCount desc
), QuestionsWithAllInfo as (
    select
        rp.Id as QuestionId,
        rp.CreationDate as QuestionCreation,
        rp.Score as QuestionScore,
        rp.ViewCount as QuestionViews,
        rp.OwnerUserId,
        u.DisplayName,
        badge_ranks.BadgeCount as UserGoldBadges,
        -- computational complex expression of score with sqrt and log, null-safe logic and string manipulation
        sqrt(abs(rp.Score)) * log(coalesce(nullif(rp.ViewCount,0),1) + 1)::float / nullif(1 + nullif(up.TotalDown,0),1)::float  as AdjustedScore,
        vw.Comments as CommentCount,
        row_number() over (partition by rp.Id order by rp.CreationDate desc) as rn
    from RecursivePosts rp
    left join Users u on rp.OwnerUserId = u.Id
    left join UserBadgeRanks badge_ranks on u.Id = badge_ranks.UserId and badge_ranks.Class = 1 and badge_ranks.rn = 1
    left join (
        select PostId, count(*) as Comments from Comments group by PostId
    ) vw on vw.PostId = rp.Id
    left join (
        select v.PostId, 
               sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUp,
               sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDown
        from Votes v
        group by v.PostId
    ) up on up.PostId = rp.Id
    where rp.Depth = 0
)
select 
  q.QuestionId,
  q.DisplayName,
  concat(substring(coalesce(p.Body,'<empty>'),1,80), ' ...') as Snippet,
  case when p.AcceptedAnswerId is not null then 'Has Accepted Answer' else 'No Accepted Answer' end as AnswerStatus,
  q.QuestionCreation,
  q.QuestionScore,
  q.QuestionViews,
  q.AdjustedScore,
  q.UserGoldBadges,
  to_char(q.CommentCount,'9999') as FamousnessVisual,
  ph.PostHistoryTypeId,
  ph.Text as LastPostHistoryText,
  lt.Name as LinkTypeName,
  coalesce(lt2.Name, 'No Link') as RelatedLinkTypeName,
  coalesce(pb.TotalUp,0) as PostUpVotes,
  coalesce(pb.TotalDown,0) as PostDownVotes,
  coalesce(pl.TotalLinks,0) as LinkCount,
  row_number() over (partition by q.DisplayName order by q.AdjustedScore desc) as RankByUser
from QuestionsWithAllInfo q
left join Posts p on p.Id = q.QuestionId
left join LatestPostHistoryPerPost ph on ph.PostId = p.Id
left join PostLinks plnk on plnk.PostId = p.Id
left join LinkTypes lt on lt.Id = plnk.LinkTypeId
left join (
    select rl.PostId, rl.RelatedPostId, lt.Id as LinkTypeId, lt.Name
    from PostLinks rl
    inner join LinkTypes lt on lt.Id = rl.LinkTypeId
    where rl.LinkTypeId = 3
) pl on pl.PostId = p.Id
left join (
    select 
        v.PostId,
        sum(case when v.VoteTypeId=2 then 1 else 0 end) as TotalUp,
        sum(case when v.VoteTypeId=3 then 1 else 0 end) as TotalDown
    from Votes v 
    group by v.PostId
) pb on pb.PostId = p.Id
left join LinkTypes lt2 on lt2.Id = pl.LinkTypeId
where q.RankByUser <= 10
union all
select
    t.Id,
    'TAG: ' || t.TagName as DisplayName,
    'Excerpt: ' || substring(p.Body,1,80) || ' ...',
    'TagInfo',
    p.CreationDate,
    p.Score,
    p.ViewCount,
    (sqrt(t.Count) + log(p.Score + abs(p.ViewCount) + 2))::float as AdjustedScore,
    null,
    'N/A' as FamousnessVisual,
    null,
    null,
    null,
    null,
    null,
    null
from CTE_ExpensiveTags t
left join Posts p on p.Id = t.ExcerptPostId
order by 8 desc, 5 asc
limit 50;