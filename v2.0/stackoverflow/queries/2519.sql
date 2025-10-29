-- {"query": "2519.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1137}
with TopUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
        row_number() over (order by u.Reputation desc, u.CreationDate) as rn
    from Users u
    where u.Reputation > 1000
),
UserBadgeCounts as (
    select b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
RecentActivePosts as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.Title, p.Tags,
        p.CreationDate, p.LastActivityDate,
        rank() over (partition by p.OwnerUserId order by p.LastActivityDate desc) as post_rank
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostAnswerCounts as (
    select q.Id as QuestionId,
        coalesce(count(a.Id), 0) as AnswerCount,
        coalesce(avg(a.Score), 0) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
ClosedQuestionsCTE as (
    select ph.PostId, ph.CreationDate as CloseDate, crt.Name as CloseReason
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
),
ComplexUserStats as (
    select u.Id, u.DisplayName, u.Reputation,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 and
             exists (
               select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 2 and v.CreationDate > u.CreationDate
             )
        ) as QuestionsWithUpvotes,
        (select count(*) from Comments c where c.UserId = u.Id and c.CreationDate > u.CreationDate) as CommentsCount,
        (select sum(v.BountyAmount) from Votes v where v.UserId = u.Id and v.BountyAmount is not null) as TotalBountyGiven
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    where u.Reputation > 500
)
select cs.Id as UserId, cs.DisplayName, cs.Reputation,
    cs.GoldBadges, cs.SilverBadges, cs.BronzeBadges,
    cs.QuestionsWithUpvotes, cs.CommentsCount, cs.TotalBountyGiven,
    coalesce(pa.AnswerCount,0) as TotalAnswersForUserQuestions,
    coalesce(pa.AvgAnswerScore,0) as AvgAnswerScoreForUserQuestions,
    coalesce(clq.CloseDate, null) as LastQuestionCloseDate,
    clq.CloseReason,
    dup.DuplicateCount,
    (
      'Rep:' || cs.Reputation || ' | Gold:' || cs.GoldBadges || '/' || cs.SilverBadges || '/' || cs.BronzeBadges || ' | ' ||
      'QUp:' || cs.QuestionsWithUpvotes || ' | Comments:' || cs.CommentsCount || ' | Bounty:' || coalesce(cs.TotalBountyGiven,0) || ' | ' ||
      'Ans:' || coalesce(pa.AnswerCount,0) || ' (AvgScore:' || round(coalesce(pa.AvgAnswerScore,0),2) || ')'
    ) as UserSummary
from ComplexUserStats cs
left join lateral (
    select sum(ac.AnswerCount) as AnswerCount, avg(ac.AvgAnswerScore) as AvgAnswerScore
    from PostAnswerCounts ac
    join Posts pq on pq.Id = ac.QuestionId
    where pq.OwnerUserId = cs.Id
) pa on true
left join lateral (
    select c.CloseDate, c.CloseReason
    from ClosedQuestionsCTE c
    join Posts q on q.Id = c.PostId and q.OwnerUserId = cs.Id
    order by c.CloseDate desc limit 1
) clq on true
left join lateral (
    select count(*) as DuplicateCount
    from Posts p
    join DuplicateLinks dl on dl.PostId = p.Id
    where p.OwnerUserId = cs.Id
) dup on true
where (cs.GoldBadges + cs.SilverBadges + cs.BronzeBadges) > 2
group by cs.Id, cs.DisplayName, cs.Reputation, cs.GoldBadges, cs.SilverBadges, cs.BronzeBadges,
         cs.QuestionsWithUpvotes, cs.CommentsCount, cs.TotalBountyGiven,
         pa.AnswerCount, pa.AvgAnswerScore, clq.CloseDate, clq.CloseReason, dup.DuplicateCount
order by cs.Reputation desc, cs.GoldBadges desc
limit 100;