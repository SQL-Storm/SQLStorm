-- {"query": "984.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1663} 
with recursive UserBadgeCounts as (
  select
    u.Id as UserId,
    u.DisplayName,
    coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
    coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
    coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges
  from Users u
  left join Badges b on u.Id = b.UserId
  group by u.Id, u.DisplayName
),
PostWithAnswerStats as (
  select
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.AcceptedAnswerId,
    case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
    (select count(*) from Posts a where a.ParentId = p.Id and a.Score > 0) as PositiveAnswersCount,
    (select count(*) from Posts a where a.ParentId = p.Id and a.Score < 0) as NegativeAnswersCount
  from Posts p
  where p.PostTypeId = 1
),
RankedPosts as (
  select
    pws.*,
    dense_rank() over (partition by extract(year from pws.CreationDate) order by pws.Score desc, pws.ViewCount desc) as YearlyRank,
    row_number() over (partition by pws.OwnerUserId order by pws.Score desc) as UserTopPostRank
  from PostWithAnswerStats pws
),
RecentCommentsPerPost as (
  select distinct on (c.PostId)
    c.PostId,
    c.Id as CommentId,
    c.UserId as CommentUserId,
    c.UserDisplayName as CommentUserDisplayName,
    c.Score as CommentScore,
    c.Text as CommentText,
    c.CreationDate as CommentDate
  from Comments c
  order by c.PostId, c.CreationDate desc
),
PostsWithLinkInfo as (
  select
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount,
    count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedPostsCount
  from Posts p
  left join PostLinks pl on p.Id = pl.PostId
  left join LinkTypes lt on pl.LinkTypeId = lt.Id
  group by p.Id, p.Title, p.Tags, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount
),
UserActivity as (
  select
    u.Id,
    u.DisplayName,
    count(distinct p.Id) as TotalPosts,
    count(distinct case when p.PostTypeId=1 then p.Id else null end) as TotalQuestions,
    count(distinct case when p.PostTypeId=2 then p.Id else null end) as TotalAnswers,
    count(distinct c.Id) as TotalComments,
    coalesce(sum(vtCount.UpVotes), 0) as TotalUpVotes,
    coalesce(sum(vtCount.DownVotes), 0) as TotalDownVotes,
    max(u.Reputation) as MaxReputation
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join (
    select
      v.UserId,
      sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
      sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
  ) vtCount on vtCount.UserId = u.Id
  group by u.Id, u.DisplayName
),
CloseReasonCounts as (
  select
    cht.Id as CloseReasonTypeId,
    cht.Name as CloseReasonName,
    count(ph.Id) as CloseCount
  from PostHistory ph
  inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
  inner join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
  where ph.PostHistoryTypeId = 10
  group by cht.Id, cht.Name
),
TopPostsWithComments as (
  select
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    coalesce(rc.CommentText, '(No recent comments)') as RecentComment,
    coalesce(rc.CommentUserDisplayName, '(Anonymous)') as RecentCommentUser,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.MaxReputation
  from RankedPosts rp
  left join RecentCommentsPerPost rc on rp.Id = rc.PostId
  left join Users u on rp.OwnerUserId = u.Id
  left join UserBadgeCounts ub on ub.UserId = rp.OwnerUserId
  left join UserActivity ua on ua.Id = rp.OwnerUserId
  where rp.YearlyRank <= 5 and rp.HasAcceptedAnswer = 1
),
RecursiveTagExplode(tagname, postid, level) as (
  select
    trim(both '<>' from unnest(string_to_array(coalesce(p.Tags, ''), '><'))) as tagname,
    p.Id as postid,
    1 as level
  from Posts p
  where p.PostTypeId = 1 and p.Tags is not null
  union all
  select
    null, null, level + 1
  from RecursiveTagExplode
  where level < 1
)
select distinct
  tpt.PostTypeId,
  pt.Name as PostTypeName,
  tpt.Id as PostId,
  tpt.Title,
  tpt.CreationDate,
  tpt.Score,
  tpt.ViewCount,
  tpt.AnswerCount,
  tpt.RecentCommentUser,
  left(tpt.RecentComment, 150) as RecentCommentExcerpt,
  tpt.GoldBadges,
  tpt.SilverBadges,
  tpt.BronzeBadges,
  tpt.TotalPosts,
  tpt.TotalQuestions,
  tpt.TotalAnswers,
  tpt.TotalComments,
  tpt.TotalUpVotes,
  tpt.TotalDownVotes,
  tpt.MaxReputation,
  crc.CloseReasonName,
  coalesce(pl.DuplicateLinksCount, 0) as DuplicateLinksCount,
  coalesce(pl.LinkedPostsCount, 0) as LinkedPostsCount
from TopPostsWithComments tpt
inner join PostTypes pt on pt.Id = tpt.PostTypeId
left join Posts p on p.Id = tpt.Id
left join PostLinks pl on pl.PostId = p.Id
left join CloseReasonCounts crc on 1=1
where
  (tpt.Title is not null and tpt.Title <> '')
  and (tpt.Score > 10 or tpt.ViewCount > 1000)
  and (tpt.GoldBadges + tpt.SilverBadges + tpt.BronzeBadges) > 0
order by tpt.Score desc, tpt.ViewCount desc, tpt.CreationDate desc
limit 100;