-- {"query": "477.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1709} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(u.Reputation, 0) as OwnerReputation,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.TagName is not null
),
TopTags as (
    select Id, TagName, Count, AnswerCount, ViewCount, OwnerReputation
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostVoteStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(v.BountyAmount) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        u.DisplayName as Answerer,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionsWithTopAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName as QuestionOwner,
        r.AnswerRank,
        r.Id as AnswerId,
        r.Score as AnswerScore,
        r.CreationDate as AnswerCreationDate,
        r.Answerer
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    left join RankedAnswers r on r.ParentId = q.Id and r.AnswerRank <= 3
    where q.PostTypeId = 1
),
ClosedQuestions as (
    select
        ph.PostId,
        min(ph.CreationDate) as ClosedDate,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
QuestionStats as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionCreationDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.QuestionOwner,
        coalesce(cq.ClosedDate, null) as ClosedDate,
        coalesce(cq.CloseReason, 'Open') as CloseReason,
        json_agg(json_build_object(
            'AnswerId', q.AnswerId,
            'AnswerScore', q.AnswerScore,
            'AnswerCreationDate', q.AnswerCreationDate,
            'Answerer', q.Answerer,
            'AnswerRank', q.AnswerRank
        ) order by q.AnswerRank) filter (where q.AnswerId is not null) as TopAnswers
    from QuestionsWithTopAnswers q
    left join ClosedQuestions cq on cq.PostId = q.QuestionId
    group by q.QuestionId, q.Title, q.QuestionCreationDate, q.QuestionScore, q.ViewCount, q.Tags, q.QuestionOwner, cq.ClosedDate, cq.CloseReason
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as AnswersPosted,
        count(distinct c.Id) over (partition by u.Id order by c.CreationDate rows between unbounded preceding and current row) as CommentsMade,
        sum(coalesce(v.BountyAmount,0)) over (partition by u.Id order by v.CreationDate rows between unbounded preceding and current row) as TotalBountyGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9)
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        coalesce(ua.QuestionsPosted,0) as QuestionsPosted,
        coalesce(ua.AnswersPosted,0) as AnswersPosted,
        coalesce(ua.CommentsMade,0) as CommentsMade,
        coalesce(ua.TotalBountyGiven,0) as TotalBountyGiven
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join (
        select distinct on (UserId) UserId, QuestionsPosted, AnswersPosted, CommentsMade, TotalBountyGiven
        from UserActivityWindow
        order by UserId, CreationDate desc nulls last
    ) ua on ua.UserId = u.Id
)
select
    q.QuestionId,
    q.Title,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.Tags,
    q.QuestionOwner,
    q.CloseReason,
    coalesce(array_length(string_to_array(q.Tags, '><'),1), 0) as TagCount,
    (select count(*) from Posts a where a.ParentId = q.QuestionId and a.Score > 10) as HighScoreAnswerCount,
    (select count(*) from Votes v where v.PostId = q.QuestionId and v.VoteTypeId = 2) as QuestionUpVotes,
    (select count(*) from Votes v where v.PostId = q.QuestionId and v.VoteTypeId = 3) as QuestionDownVotes,
    q.TopAnswers,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.QuestionsPosted,
    ubs.AnswersPosted,
    ubs.CommentsMade,
    ubs.TotalBountyGiven,
    case
        when q.CloseReason = 'Duplicate' then 'Needs Review'
        when q.CloseReason = 'Off-topic' then 'Off Topic'
        when q.CloseReason = 'Open' and q.QuestionScore > 100 then 'Hot Question'
        else 'Normal'
    end as QuestionStatus
from QuestionStats q
left join UserBadgeSummary ubs on ubs.UserId = (select OwnerUserId from Posts where Id = q.QuestionId)
where q.QuestionCreationDate > now() - interval '1 year'
order by q.QuestionScore desc nulls last, q.ViewCount desc nulls last
limit 50;