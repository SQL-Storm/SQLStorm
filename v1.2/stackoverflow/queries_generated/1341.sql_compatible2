with recursive RankedPosts as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           p.Title, p.Tags, p.AcceptedAnswerId,
           row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId in (1, 2)
),
UserBadgeStats as (
    select u.Id as UserId,
           count(b.Id) filter (where b.Class = 1) as GoldBadges,
           count(b.Id) filter (where b.Class = 2) as SilverBadges,
           count(b.Id) filter (where b.Class = 3) as BronzeBadges,
           max(b.Date) as LatestBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
AnswerDetails as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId, a.CreationDate,
           u.DisplayName, u.Reputation,
           (select count(*) from Comments c where c.PostId = a.Id and c.CreationDate > a.CreationDate) as LaterCommentCount,
           row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as PositionByScore
    from Posts a
    inner join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
MaxScorePerQuestion as (
    select ParentId as QuestionId, max(Score) as MaxAnswerScore
    from Posts 
    where PostTypeId = 2 
    group by ParentId
),
QuestionWithAcceptedFromRejectedAnswer as (
   select q.Id as QuestionId, q.AcceptedAnswerId, a.Id as AnswerId, a.Score, a.OwnerUserId, 
      case when a.Id = q.AcceptedAnswerId then 'Y' else 'N' end as maxcase
   from Posts q
   join Posts a on a.ParentId = q.Id and a.Score < q.Score 
   where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
FinalStats as (
    select rp.Id PostId,
           rp.PostTypeId,
           rp.OwnerUserId,
           rp.CreationDate,
           rp.Score,
           rp.ViewCount,
           rp.Title,
           rp.Tags,
           u.DisplayName,
           u.Reputation,
           u.CreationDate as UserCreation,
           coalesce(ub.GoldBadges, 0) as GoldBadges,
           coalesce(ub.SilverBadges, 0) as SilverBadges,
           coalesce(ub.BronzeBadges, 0) as BronzeBadges,
           ub.LatestBadgeDate,
           arr.AnswerCount,
           arr.AcceptedAnswerScore,
           mdlv.MaxAnswerScore,
           ad.PositionByScore,
           length(coalesce(rp.Tags, '')) - length(replace(coalesce(rp.Tags,''), '><', '')) + 1 as TagsCount,
           case 
              when u.Reputation is null then 'No Reputation'
              when abs(u.Reputation - rp.Score) > 1000 then 'High Disparity'
              else 'Normal' 
           end as ReputationScoreDisparity,
           case when rp.ViewCount is null then 0 else rp.ViewCount end * rp.Score as WeightedScoreViews,
           regexp_replace(coalesce(u.WebsiteUrl,''), '^(https?://)?(www\.)?([^/]+).*$', '\3') as Domain,
           exists (
             select 1 from Tags t where position(('><' || t.TagName || '><') in coalesce(rp.Tags, '')) > 0 and t.Count > 10000
           ) as HasPopularTag,
           first_value(comm.comments_count) over (partition by rp.Id order by rp.CreationDate rows between unbounded preceding and unbounded following) as FirstSelectedCommentCount
    from RankedPosts rp
    left join Users u on u.Id = rp.OwnerUserId
    left join UserBadgeStats ub on ub.UserId = rp.OwnerUserId
    left join (
        select p.Id, p.AnswerCount,
           (select pa.Score from Posts pa where pa.Id = p.AcceptedAnswerId) as AcceptedAnswerScore
        from Posts p
        where p.PostTypeId = 1
    ) arr on arr.Id = rp.Id
    left join MaxScorePerQuestion mdlv on mdlv.QuestionId = rp.Id
    left join AnswerDetails ad on ad.QuestionId = rp.Id and ad.PositionByScore = 1
    left join lateral (
      select count(*) as comments_count
      from Comments c
      where c.PostId = rp.Id
    ) comm on true
    where rp.rn <= 100
    group by rp.Id, rp.PostTypeId, rp.OwnerUserId, rp.CreationDate, rp.Score, rp.ViewCount, rp.Title, rp.Tags,
             u.DisplayName, u.Reputation, u.CreationDate, u.WebsiteUrl, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.LatestBadgeDate,
             arr.AnswerCount, arr.AcceptedAnswerScore, mdlv.MaxAnswerScore, ad.PositionByScore, comm.comments_count
)
select fs.PostId, fs.PostTypeId, fs.Title, fs.Score, fs.ViewCount, fs.OwnerUserId, fs.DisplayName,
       fs.Reputation, fs.UserCreation, fs.GoldBadges, fs.SilverBadges, fs.BronzeBadges, fs.LatestBadgeDate,
       fs.AnswerCount, fs.AcceptedAnswerScore, fs.MaxAnswerScore, fs.PositionByScore,
       fs.TagsCount, fs.ReputationScoreDisparity, fs.WeightedScoreViews, fs.Domain, fs.HasPopularTag,
       fs.FirstSelectedCommentCount
from FinalStats fs
where fs.Score > 10
and fs.HasPopularTag = true
and fs.Reputation > 1000
and (fs.LatestBadgeDate is null or fs.LatestBadgeDate < (cast('2024-10-01' as date) - interval '365 days'))
union
select p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName,
       u.Reputation, u.CreationDate, 0, 0, 0, NULL,
       0, NULL, NULL, NULL,
       0, 'Normal', 0, '', false,
       0
from Posts p
join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.Score < 0
  and not exists (select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 4)
  and p.Id in (
      select pl.RelatedPostId from PostLinks pl where pl.LinkTypeId = 3
  )
order by Score desc, ViewCount desc
limit 200;