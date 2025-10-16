-- {"query": "173.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1412} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
TopScoringAnswers as (
    select
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        p.Score,
        p.CreationDate,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2
),
QuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerId,
        u.DisplayName as AcceptedAnswerOwnerName
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) over (partition by u.Id) as TotalBountyEarned,
        count(v.Id) filter (where v.VoteTypeId = 2) over (partition by u.Id) as UpVotesReceived,
        count(v.Id) filter (where v.VoteTypeId = 3) over (partition by u.Id) as DownVotesReceived
    from Users u
    left join Votes v on v.UserId = u.Id
)
select
    q.QuestionId,
    q.Title,
    q.QuestionCreation,
    q.QuestionScore,
    q.QuestionViews,
    q.AcceptedAnswerId,
    q.AcceptedAnswerScore,
    q.AcceptedAnswerOwnerId,
    q.AcceptedAnswerOwnerName,
    coalesce(dc.CloseCount, 0) as CloseVotes,
    coalesce(dc.CloseReason, 'None') as CloseReason,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TagBasedBadges,
    ua.AnswerId as TopAnswerId,
    ua.Score as TopAnswerScore,
    ua.AnswerOwner as TopAnswerOwner,
    rt.TagName,
    rt.Count as TagUsageCount,
    rt.AnswerCount as TagAnswerCount,
    rt.ViewCount as TagViewCount,
    rt.Score as TagScore,
    ur.Reputation as AnswerOwnerReputation,
    ur.TotalBountyEarned,
    ur.UpVotesReceived,
    ur.DownVotesReceived,
    case
        when q.QuestionScore > 100 then 'High Score'
        when q.QuestionScore between 50 and 100 then 'Medium Score'
        else 'Low Score'
    end as ScoreCategory,
    case
        when q.QuestionViews > 10000 then 'Highly Viewed'
        when q.QuestionViews between 1000 and 10000 then 'Moderately Viewed'
        else 'Low Views'
    end as ViewCategory,
    concat_ws(' | ', substring(q.Title from 1 for 50), 'Tags:', coalesce(rt.TagName, 'No Tags')) as TitleTagSummary
from QuestionsWithAcceptedAnswers q
left join CloseReasonCounts dc on dc.PostId = q.QuestionId
left join UserBadgeStats us on us.UserId = q.AcceptedAnswerOwnerId
left join TopScoringAnswers ua on ua.QuestionId = q.QuestionId and ua.AnswerRank = 1
left join RecursiveTagCounts rt on rt.TagName = any(string_to_array(replace(replace(q.Title, '<', ''), '>', ''), ' '))
left join UserReputationWindow ur on ur.Id = q.AcceptedAnswerOwnerId
where q.QuestionCreation > now() - interval '1 year'
  and (dc.CloseCount is null or dc.CloseCount < 5)
order by q.QuestionScore desc nulls last, q.QuestionViews desc nulls last
limit 100;