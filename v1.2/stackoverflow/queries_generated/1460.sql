-- {"query": "1460.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1391} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        1 as Level
    from Tags t
    union all
    select
        rt.TagId,
        rt.TagName || '_child' as TagName,
        rt.Count / 2,
        r.Level + 1
    from RecursiveTagCounts r
    join Tags rt on rt.Id = r.TagId
    where r.Level < 2
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        coalesce(sum(com.Score),0) as TotalCommentScore,
        max(p.CreationDate) maxPostDate,
        min(p.CreationDate) minPostDate,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        coalesce((select count(*) from Badges b where b.UserId = u.Id and b.Class = 1),0) as GoldBadges,
        coalesce((select count(*) from Badges b where b.UserId = u.Id and b.Class = 2),0) as SilverBadges,
        coalesce((select count(*) from Badges b where b.UserId = u.Id and b.Class = 3),0) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments com on com.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoresWindow as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as RN_score_desc,
        avg(p.Score) over(partition by p.OwnerUserId) as AvgUserPostScore,
        max(p.ViewCount) over (partition by p.OwnerUserId) as MaxUserPostViewCount
    from Posts p
    where p.OwnerUserId is not null
),
ClosePostDetails as (
    select p.Id, cb.Name as CloseReason, ph.CreationDate as CloseDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cb on cb.Id = cast(ph.Comment as int)  -- Comment contains close reason Id when PostHistoryTypeId=10
    where ph.PostHistoryTypeId = 10
),
PostWithLinkTypes as (
    select pl.PostId, lt.Name as LinkTypeName, pl.RelatedPostId
    from PostLinks pl
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
),
QuestionsWithTopAnswers as (
    select 
        q.Id as QuestionId, 
        q.Title, 
        q.CreationDate as QuestionDate,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        a.OwnerUserId as AnswerOwnerId,
        a.ParentId
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
VPnGr as (
   select
      q.Id,
      q.Title,
      q.Tags,
      q.OwnerUserId,
      sum(v.VoteTypeId = 2::int)::int as UpVotes,
      sum(v.VoteTypeId = 3::int)::int as DownVotes,
      sum(v.VoteTypeId = 8::int)*coalesce(v.BountyAmount,0)::int as BountyStarted,
      sum(v.VoteTypeId = 9::int)*coalesce(v.BountyAmount,0)::int as BountyClosed
   from
     Posts q
     left join Votes v on v.PostId = q.Id
   where q.PostTypeId = 1
   group by q.Id, q.Title, q.Tags, q.OwnerUserId
)
select distinct ua.Id as UserId,
       ua.DisplayName,
       ua.TotalPosts,
       ua.QuestionCount,
       ua.AnswerCount,
       ua.GoldBadges,
       ua.SilverBadges,
       ua.BronzeBadges,
       max(cpd.CloseReason) over (partition by ua.Id) as MostFrequentCloseReason,
       psc.AvgUserPostScore,
       psc.MaxUserPostViewCount,
       substring(coalesce(array_to_string(string_to_array(max(p.Tags), '><'), ', '), '') from 1 for 200) as SampleTags,
       string_agg(
         distinct concat_ws(' - ', pllt.LinkTypeName, (select pt.Name from PostTypes pt where pt.Id = p.PostTypeId)),
         '; ' order by pllt.LinkTypeName
         ) as LinkTypesOnUserPosts,
       coalesce(
         (select q.QuestionId from QuestionsWithTopAnswers qwa
          join QuestionsWithTopAnswers q on q.Id = qwa.QuestionId
          where qwa.AnswerOwnerId = ua.Id
          order by qwa.AnswerScore desc limit 1
         ), -1) as BestAnswerForQuestionId,
        VPnGr.UpVotes,
        VPnGr.DownVotes,
        (VPnGr.BountyClosed - VPnGr.BountyStarted) as BountyNet
from UserActivity ua
left join PostScoresWindow psc on psc.OwnerUserId = ua.Id
left join Posts p on p.OwnerUserId = ua.Id
left join PostWithLinkTypes pllt on pllt.PostId = p.Id
left join ClosePostDetails cpd on cpd.Id = p.Id
left join VPnGr on VPnGr.OwnerUserId = ua.Id
where ua.TotalPosts > 0
group by ua.Id, ua.DisplayName, ua.TotalPosts, ua.QuestionCount, ua.AnswerCount, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, psc.AvgUserPostScore, psc.MaxUserPostViewCount, VPnGr.UpVotes, VPnGr.DownVotes, VPnGr.BountyClosed, VPnGr.BountyStarted
having max(cpd.CloseReason) is not null or ua.QuestionCount > 5
order by ua.GoldBadges desc, ua.TotalPosts desc
limit 25;