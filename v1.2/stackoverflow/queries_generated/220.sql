-- {"query": "220.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1566} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(vt_up.VoteCount),0) as TotalUpVotes,
        coalesce(sum(vt_down.VoteCount),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vt_up on vt_up.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vt_down on vt_down.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by t.TagName order by p.Score desc, p.ViewCount desc) as TagRank
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionDetails as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.AcceptedAnswerId,
        coalesce(ac.AnswerCount,0) as AnswerCount,
        coalesce(ac.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ac.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(ac.AnonymousAnswers,0) as AnonymousAnswers,
        p.FavoriteCount,
        p.ClosedDate,
        p.Tags,
        p.LastActivityDate,
        p.CommentCount,
        p.Body,
        p.ContentLicense,
        p.CommunityOwnedDate,
        p.LastEditDate,
        p.LastEditorUserId,
        p.LastEditorDisplayName,
        p.OwnerDisplayName,
        p.ParentId,
        p.AcceptedAnswerId,
        p.Score - coalesce(ac.AvgAnswerScore,0) as ScoreVsAvgAnswerScore
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join AnswerStats ac on ac.QuestionId = p.Id
    where p.PostTypeId = 1
),
UserActivityWithBadges as (
    select
        ua.*,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TotalBadges,0) as TotalBadges
    from RecursiveUserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
),
QuestionsWithCloseReasons as (
    select
        qd.*,
        pcr.CloseReason,
        pcr.CloseDate
    from QuestionDetails qd
    left join PostCloseReasons pcr on pcr.PostId = qd.Id
),
RankedQuestions as (
    select
        qcr.*,
        rank() over (partition by qcr.CloseReason order by qcr.Score desc nulls last, qcr.ViewCount desc nulls last) as CloseReasonRank,
        dense_rank() over (order by qcr.Score desc nulls last, qcr.ViewCount desc nulls last) as OverallRank
    from QuestionsWithCloseReasons qcr
),
FinalOutput as (
    select
        rq.Id as QuestionId,
        rq.Title,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.AvgAnswerScore,
        rq.MaxAnswerScore,
        rq.AnonymousAnswers,
        rq.FavoriteCount,
        rq.CloseReason,
        rq.CloseDate,
        rq.CreationDate,
        rq.OwnerUserId,
        ua.DisplayName as OwnerName,
        ua.Reputation as OwnerReputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TotalBadges,
        rq.Tags,
        rq.LastActivityDate,
        rq.CommentCount,
        rq.ScoreVsAvgAnswerScore,
        rq.ClosedDate,
        rq.CommunityOwnedDate,
        rq.LastEditDate,
        rq.LastEditorUserId,
        rq.LastEditorDisplayName,
        rq.OwnerDisplayName,
        rq.ParentId,
        rq.AcceptedAnswerId,
        rq.OverallRank,
        rq.CloseReasonRank,
        -- Complex string expression: concatenate tags with user display name and question title length
        concat(
            'Tags: ', coalesce(rq.Tags, 'NoTags'), ' | ',
            'Owner: ', coalesce(ua.DisplayName, 'Unknown'), ' | ',
            'TitleLength: ', length(coalesce(rq.Title, ''))
        ) as TagOwnerTitleInfo
    from RankedQuestions rq
    left join UserActivityWithBadges ua on ua.UserId = rq.OwnerUserId
    where rq.Score > 10 or rq.AnswerCount > 5
)
select *
from FinalOutput
where (GoldBadges + SilverBadges + BronzeBadges) > 5
order by OverallRank
limit 100;