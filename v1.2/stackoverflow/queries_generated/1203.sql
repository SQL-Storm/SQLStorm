-- {"query": "1203.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1618} 
with RecursivePostLinks as (
    select pl.PostId, pl.RelatedPostId, pl.LinkTypeId, 1 as Depth
    from PostLinks pl
    where pl.LinkTypeId = 3 -- duplicates
    union all
    select rpl.PostId, pl.RelatedPostId, pl.LinkTypeId, rpl.Depth + 1
    from RecursivePostLinks rpl
    join PostLinks pl on pl.PostId = rpl.RelatedPostId and pl.LinkTypeId = 3
    where rpl.Depth < 5
),
UserBadgeAgg as (
    select b.UserId,
           count(*) filter (where b.Class=1) as GoldBadgeCount,
           count(*) filter (where b.Class=2) as SilverBadgeCount,
           count(*) filter (where b.Class=3) as BronzeBadgeCount,
           max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TopActiveUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           coalesce(uba.GoldBadgeCount, 0) as GoldBadges,
           coalesce(uba.SilverBadgeCount, 0) as SilverBadges,
           coalesce(uba.BronzeBadgeCount, 0) as BronzeBadges,
           u.Views,
           dense_rank() over (order by u.Reputation desc, u.Views desc) as Rank
    from Users u
    left join UserBadgeAgg uba on uba.UserId = u.Id
    where u.Reputation > 1000
),
PostScoresAndRanks as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate,
           p.Title, p.Score, p.ViewCount,
           row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank,
           p.Tags,
           case when p.ClosedDate is null then 0 else 1 end as IsClosed,
           case 
               when length(coalesce(p.Body, '')) > 1000 then 'Long Body'
               when length(coalesce(p.Body, '')) between 500 and 1000 then 'Medium Body'
               else 'Short Body' 
           end as BodyLengthCategory
    from Posts p
    where p.PostTypeId in (1, 2)
),
AcceptedAnswerAnalysis as (
    select q.Id as QuestionId, q.Title as QuestionTitle, q.OwnerUserId as QuestionOwner,
           a.Id as AcceptedAnswerId, a.OwnerUserId as AcceptedOwner, a.Score as AcceptedAnswerScore,
           (select count(1) from Comments c where c.PostId = a.Id) as AcceptedAnswerCommentCount,
           (select count(distinct ph.PostId) from PostHistory ph where ph.UserId = a.OwnerUserId and ph.PostId = a.Id) as RevisionCountOnAccepted,
           (select count(1) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AcceptedAnswerUpVotes,
           (select count(1) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AcceptedAnswerDownVotes
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
WindowAggregation as (
    select psr.*,
           avg(psr.Score) over (partition by psr.OwnerUserId) as UserAvgPostScore,
           sum(case when psr.IsClosed = 1 then 1 else 0 end) over (partition by psr.OwnerUserId) as UserClosedPostsCount,
           min(psr.CreationDate) over (partition by psr.OwnerUserId) as UserFirstPostDate,
           max(psr.CreationDate) over (partition by psr.OwnerUserId) as UserLastPostDate
    from PostScoresAndRanks psr
),
ComplexStringMatchAgg as (
    select psr.OwnerUserId,
           count(*) filter (where psr.Tags like '%<sql>%') as SqlTagCount,
           count(*) filter (where psr.Tags like '%<java>%') as JavaTagCount,
           count(*) filter (where psr.Tags like '%<c#>%') as CSharpTagCount
    from PostScoresAndRanks psr
    group by psr.OwnerUserId
),
CloseReasonCounts as (
    select ph.UserId, crt.Name as CloseReason, count(*) as CloseReasonCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.UserId is not null
    group by ph.UserId, crt.Name
),
FinalUserAgg as (
    select u.Id, u.DisplayName,
           coalesce(tau.GoldBadges, 0) as GoldBadges,
           coalesce(tau.SilverBadges, 0) as SilverBadges,
           coalesce(tau.BronzeBadges, 0) as BronzeBadges,
           coalesce(csm.SqlTagCount, 0) as SqlTagPosts,
           coalesce(csm.JavaTagCount, 0) as JavaTagPosts,
           coalesce(csm.CSharpTagCount, 0) as CSharpTagPosts,
           coalesce(crc.CloseReasonCount, 0) as DuplicateCloseVotesCountByUser,
           wagg.UserClosedPostsCount,
           wagg.UserAvgPostScore,
           wagg.UserFirstPostDate,
           wagg.UserLastPostDate
    from Users u
    left join TopActiveUsers tau on tau.Id = u.Id
    left join ComplexStringMatchAgg csm on csm.OwnerUserId = u.Id
    left join CloseReasonCounts crc on crc.UserId = u.Id and crc.CloseReason = 'Duplicate'
    left join (
        select OwnerUserId,
               sum(case when IsClosed = 1 then 1 else 0 end) as UserClosedPostsCount,
               avg(Score) as UserAvgPostScore,
               min(CreationDate) as UserFirstPostDate,
               max(CreationDate) as UserLastPostDate
        from PostScoresAndRanks
        group by OwnerUserId
    ) wagg on wagg.OwnerUserId = u.Id
    where u.Reputation > 1000
)

select fu.Id as UserId, fu.DisplayName, fu.GoldBadges, fu.SilverBadges, fu.BronzeBadges,
       fu.SqlTagPosts, fu.JavaTagPosts, fu.CSharpTagPosts,
       fu.DuplicateCloseVotesCountByUser, fu.UserClosedPostsCount,
       round(fu.UserAvgPostScore,2) as AveragePostScore,
       fu.UserFirstPostDate, fu.UserLastPostDate,
       coalesce(aal.AcceptedAnswerScore, 0) as AcceptedAnswerScore,
       rpl.Depth as DuplicateChainDepth
from FinalUserAgg fu
left join AcceptedAnswerAnalysis aal on aal.QuestionOwner = fu.Id
left join (
    select PostId, max(Depth) as Depth
    from RecursivePostLinks
    group by PostId
) rpl on rpl.PostId = aal.AcceptedAnswerId
where 
    (fu.GoldBadges + fu.SilverBadges + fu.BronzeBadges) > 5
    and fu.UserClosedPostsCount < 10
    and fu.DuplicateCloseVotesCountByUser > 0
order by fu.GoldBadges desc, fu.UserAvgPostScore desc, fu.DisplayName
limit 100;