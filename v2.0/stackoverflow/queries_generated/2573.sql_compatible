with RecentHighScorePosts as (
    select p.Id, p.Title, p.Score, p.OwnerUserId, p.CreationDate,
      row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate > cast('2024-10-01' as date) - interval '1 year'
      and p.Score >= 10
),
UserBadgeCounts as (
    select b.UserId,
      count(case when b.Class = 1 then 1 end) as GoldBadges,
      count(case when b.Class = 2 then 1 end) as SilverBadges,
      count(case when b.Class = 3 then 1 end) as BronzeBadges,
      count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserTopQuestions as (
    select rhp.Id as PostId, rhp.Title, rhp.Score, rhp.OwnerUserId,
      u.DisplayName, u.Reputation, u.CreationDate as UserCreationDate,
      ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.TotalBadges,
      count(c.Id) as CommentsCount,
      max(ph.CreationDate) as LastEditDate
    from RecentHighScorePosts rhp
    join Users u on u.Id = rhp.OwnerUserId
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join Comments c on c.PostId = rhp.Id
    left join PostHistory ph on ph.PostId = rhp.Id and ph.PostHistoryTypeId in (4,5,6)
    where rhp.rn = 1
    group by rhp.Id, rhp.Title, rhp.Score, rhp.OwnerUserId, u.DisplayName, u.Reputation, u.CreationDate,
      ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.TotalBadges
),
PostDuplicateInfo as (
    select pl.PostId, count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
AcceptedAnswerVotes as (
    select a.Id as AnswerId, a.ParentId as QuestionId, 
      count(case when v.VoteTypeId = 2 then 1 end) as AnswerUpVotes,
      count(case when v.VoteTypeId = 3 then 1 end) as AnswerDownVotes
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId
),
UserActivePeriod as (
    select u.Id, u.DisplayName, 
      extract(epoch from (u.LastAccessDate - u.CreationDate))/86400 as DaysActive,
      case when u.LastAccessDate is null or u.CreationDate is null then null else (u.LastAccessDate - u.CreationDate) end as ActiveInterval,
      u.Reputation
    from Users u
),
ComplexSearch as (
    select p.Id, p.Title, p.Score,
      (char_length(coalesce(p.Body, '')) - char_length(replace(coalesce(p.Body, ''), 'SQL', ''))) / 3 as SQLKeywordCount,
      array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'),1) as TagCount,
      p.ViewCount, p.FavoriteCount,
      case when p.ClosedDate is null then false else true end as IsClosed,
      case when p.AcceptedAnswerId is not null then true else false end as HasAcceptedAnswer
    from Posts p
    where p.PostTypeId = 1
      and p.Score > 0
      and p.FavoriteCount > 0
      and (p.Tags like '%<sql>%'
           or p.Tags like '%<performance>%'
           or (p.Title ilike '%performance%' and p.Body ilike '%join%'))
),
FinalResults as (
    select c.Id as QuestionId, c.Title, c.Score, c.SQLKeywordCount, c.TagCount, c.ViewCount, c.FavoriteCount,
      c.IsClosed, c.HasAcceptedAnswer, coalesce(a.AnswerUpVotes,0) as AnswerUpVotes, coalesce(a.AnswerDownVotes,0) as AnswerDownVotes, coalesce(d.DuplicateCount,0) as DuplicateCount,
      u.DisplayName as OwnerDisplayName, u.Reputation as OwnerReputation,
      coalesce(b.GoldBadges,0) as GoldBadges, coalesce(b.SilverBadges,0) as SilverBadges, coalesce(b.BronzeBadges,0) as BronzeBadges, coalesce(b.TotalBadges,0) as TotalBadges,
      c.Score * 1.0 / nullif(c.TagCount,0) as ScorePerTag,
      case when c.IsClosed then 'Closed' else 'Open' end as Status,
      row_number() over (partition by u.Id order by c.Score desc, c.ViewCount desc) as UserPostRank
    from ComplexSearch c
    left join Posts p on p.Id = c.Id
    left join AcceptedAnswerVotes a on a.QuestionId = c.Id
    left join PostDuplicateInfo d on d.PostId = c.Id
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeCounts b on b.UserId = u.Id
    group by c.Id, c.Title, c.Score, c.SQLKeywordCount, c.TagCount, c.ViewCount, c.FavoriteCount,
      c.IsClosed, c.HasAcceptedAnswer, a.AnswerUpVotes, a.AnswerDownVotes, d.DuplicateCount,
      u.Id, u.DisplayName, u.Reputation,
      b.GoldBadges, b.SilverBadges, b.BronzeBadges, b.TotalBadges
)
select * from FinalResults
where UserPostRank <= 3
  and (ScorePerTag > 5 or FavoriteCount > 10)
order by OwnerReputation desc nulls last, Score desc, ViewCount desc
limit 100;