with RecursiveUserVotes as (
    select u.Id as UserId, u.DisplayName,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        row_number() over(partition by u.Id order by u.Reputation desc) as rn
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostAgg as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        p.Tags,
        u.DisplayName as OwnerDisplayName,
        cast((
          select avg(subp.Score)
          from Posts subp
          where subp.PostTypeId = 1 and subp.Tags is not null and 
            exists (
              select 1 from unnest(string_to_array(substring(subp.Tags, 2, length(subp.Tags) - 2), '><')) as tag
              where tag = tagMain.TopTag
            )
        ) as numeric(8,2)) as AvgScoreForTag
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    cross join lateral (
        select lower(trim(tag)) as TopTag
        from unnest(string_to_array(coalesce(p.Tags,'<>'), '><')) as tag
        order by lower(trim(tag)) asc
        limit 1
    ) as tagMain
),
PostsWithRanks as (
    select 
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.ViewCount,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.Tags,
      p.OwnerDisplayName,
      p.AvgScoreForTag,
      rank() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rank_by_score,
      dense_rank() over (partition by p.OwnerUserId order by p.ViewCount desc nulls last) as dense_rank_by_views,
      count(*) over (partition by p.OwnerUserId) as PostsCountByUser
    from PostAgg p
    where p.PostTypeId = 1
),
DuplicateLinks as (
    select
      pl.PostId,
      pl.RelatedPostId,
      p1.Title as QuestionTitle,
      p2.Title as DuplicateOf
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
BadgesWithRanks as (
    select 
      b.*,
      row_number() over (partition by b.UserId order by b.Date desc) as rn
    from Badges b
),
LastPostEdits as (
    select
      ph.PostId,
      ph.CreationDate as LastEditDate,
      ph.UserId as EditorUserId,
      u.DisplayName as EditorName,
      ph.PostHistoryTypeId,
      ph.Comment
    from PostHistory ph
    left join Users u on ph.UserId = u.Id
    where ph.Id in (
      select max(Id) from PostHistory ph2 where ph2.PostId = ph.PostId
    )
)
select
    pwr.OwnerUserId,
    u.DisplayName as UserName,
    pwr.Id as QuestionId,
    pwr.Title,
    pwr.CreationDate,
    pwr.Score,
    pwr.ViewCount,
    pwr.AnswerCount,
    pwr.FavoriteCount,
    pwr.Tags,
    pwr.AvgScoreForTag,
    pwr.rank_by_score,
    pwr.dense_rank_by_views,
    pwr.PostsCountByUser,
    dupl.RelatedPostId as DuplicateOfQuestionId,
    coalesce(dupl.DuplicateOf, 'N/A') as DuplicateOfTitle,
    lastedit.LastEditDate,
    lastedit.EditorUserId,
    lastedit.EditorName,
    round((extract(epoch from (timestamp '2024-10-01 12:34:56' - u.CreationDate))/86400)::numeric, 2) as UserAccountAgeInDays,
    (select count(*) from Badges b where b.UserId = u.Id and b.Class = 1 and b.TagBased = false) as GoldNamedBadges,
    (select count(*) from Badges b where b.UserId = u.Id and b.Class in (2,3) and b.TagBased = true) as SilverBronzeTagBadges,
    string_agg(distinct substring(b.Name from 1 for 10), ', ') as SampleBadgeNames,
    (
        select max(length(t)) from unnest(string_to_array(substring(pwr.Tags, 2, length(pwr.Tags) - 2), '><')) as t
    ) as MaxTagLength,
    case
      when lastedit.LastEditDate is null then 'Never edited'
      when lastedit.LastEditDate >= timestamp '2024-10-01 12:34:56' - interval '30 days' then 'Recently Edited'
      else 'Edited before 30 days'
    end as LastEditRecency,
    coalesce(length(u.WebsiteUrl), 0) as WebsiteUrlLength
from PostsWithRanks pwr
join Users u on pwr.OwnerUserId = u.Id
left join DuplicateLinks dupl on dupl.PostId = pwr.Id
left join LastPostEdits lastedit on lastedit.PostId = pwr.Id
left join Badges b on b.UserId = u.Id
where 
    pwr.CreationDate > date '2018-01-01'
    and (
        (pwr.Tags is not null and pwr.Tags like '%python%') or 
        (pwr.Tags is not null and pwr.Tags like '%sql%') or 
        (pwr.AvgScoreForTag is not null and pwr.AvgScoreForTag > 50 and pwr.AnswerCount >= 3)
    )
group by
    pwr.OwnerUserId,
    u.DisplayName,
    pwr.Id,
    pwr.Title,
    pwr.CreationDate,
    pwr.Score,
    pwr.ViewCount,
    pwr.AnswerCount,
    pwr.FavoriteCount,
    pwr.Tags,
    pwr.AvgScoreForTag,
    pwr.rank_by_score,
    pwr.dense_rank_by_views,
    pwr.PostsCountByUser,
    dupl.RelatedPostId,
    dupl.DuplicateOf,
    lastedit.LastEditDate,
    lastedit.EditorUserId,
    lastedit.EditorName,
    u.CreationDate,
    u.WebsiteUrl,
    u.Id
order by pwr.OwnerUserId, pwr.Score desc
limit 100;