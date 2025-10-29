-- {"query": "2205.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1162} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           p.AcceptedAnswerId, cast(p.Id as varchar) as Path, 1 as Depth
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
    union all
    select c.Id, c.PostTypeId, c.OwnerUserId, c.CreationDate, c.Score, c.ViewCount, c.Tags,
           c.AcceptedAnswerId, concat(r.Path, '>', c.Id), r.Depth + 1
    from Posts c
    join RecursivePosts r on c.ParentId = r.Id
    where c.PostTypeId = 2 and c.Score > 0
),
UserBadgeCounts as (
    select u.Id as UserId,
           count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
           count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
           count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
MaxVotesPerPost as (
    select PostId, max(Score) as MaxVoteScore
    from Votes v
    join Posts p on v.PostId = p.Id
    where VoteTypeId in (2, 3)
    group by PostId
),
PostCommentsCount as (
    select PostId, count(*) as TotalComments, 
           count(distinct case when UserId is null then Id end) as AnonymousComments,
           sum(case when Text ~* '(?<!\w)(fix|bug|error|fail|issue)(?!\w)' then 1 else 0 end) as BugMentionComments
    from Comments
    group by PostId
),
RankedPosts as (
    select rp.Id, rp.PostTypeId, rp.OwnerUserId, rp.CreationDate, rp.Score, rp.ViewCount, rp.Tags, rp.AcceptedAnswerId,
           ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
           pc.TotalComments, pc.AnonymousComments, pc.BugMentionComments,
           row_number() over (partition by rp.OwnerUserId order by rp.Score desc, rp.ViewCount desc) as UserTopPostRank
    from RecursivePosts rp
    left join UserBadgeCounts ub on ub.UserId = rp.OwnerUserId
    left join PostCommentsCount pc on pc.PostId = rp.Id
    where rp.OwnerUserId is not null
),
CloseReasonStats as (
    select ph.PostId,
           sum(case when ph.PostHistoryTypeId = 10 and ph.Comment::int = 101 then 1 else 0 end) as DuplicateCloseVotes,
           sum(case when ph.PostHistoryTypeId = 10 and ph.Comment::int = 102 then 1 else 0 end) as OffTopicCloseVotes,
           sum(case when ph.PostHistoryTypeId = 10 and ph.Comment::int = 103 then 1 else 0 end) as NeedsDetailsCloseVotes,
           sum(case when ph.PostHistoryTypeId = 10 and ph.Comment::int = 104 then 1 else 0 end) as NeedsMoreFocusCloseVotes,
           sum(case when ph.PostHistoryTypeId = 10 and ph.Comment::int = 105 then 1 else 0 end) as OpinionBasedCloseVotes
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
    group by ph.PostId
)
select rp.Id as QuestionId,
       rp.Tags,
       rp.Score,
       rp.ViewCount,
       rp.CreationDate,
       rp.GoldBadges, rp.SilverBadges, rp.BronzeBadges,
       rp.TotalComments, rp.AnonymousComments, rp.BugMentionComments,
       cr.DuplicateCloseVotes, cr.OffTopicCloseVotes, cr.NeedsDetailsCloseVotes, cr.NeedsMoreFocusCloseVotes, cr.OpinionBasedCloseVotes,
       case when rp.AcceptedAnswerId is not null then 'Has Accepted Answer' else 'No Accepted Answer' end as AcceptedAnswerStatus,
       (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 2) as UpVotesCount,
       (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 3) as DownVotesCount,
       case 
         when rp.Score > 0 then round(rp.ViewCount::numeric / rp.Score,2)
         else null
       end as ViewsPerScore,
       concat_ws(' | ',
           substring(rp.Tags from 2 for length(rp.Tags)-2),
           'Depth:', rp.Depth::text,
           'UserTopPostRank:', rp.UserTopPostRank::text) as TagAndRankSummary
from RankedPosts rp
left join CloseReasonStats cr on cr.PostId = rp.Id
where rp.UserTopPostRank <= 3 and rp.Score >= 5
and (
    rp.Tags ilike '%<sql>%'
    or rp.Tags ilike '%<performance>%'
    or rp.Tags ilike '%<benchmark>%'
)
order by rp.GoldBadges desc nulls last, rp.Score desc, rp.ViewCount desc
limit 50;