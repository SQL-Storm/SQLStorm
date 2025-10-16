-- {"query": "555.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1572} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and array_length(r.Path,1) < 3
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        count(a.Id) as TotalAnswers,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as AnswersByAsker
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
LatestPostHistoryPerPost as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as HistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc, ph.Id desc
),
PostsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        lph.PostHistoryTypeId,
        lph.Comment as CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    left join LatestPostHistoryPerPost lph on p.Id = lph.PostId and lph.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes crt on crt.Id = cast(lph.Comment as int)
    where p.PostTypeId = 1
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(c.Id) as CommentCount,
        sum(vt.VoteCount) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            count(v.Id) as VoteCount
        from Votes v
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
HighActivityUsers as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.TotalVotesReceived,
        ua.UserRank
    from UserActivityWindow ua
    where ua.QuestionCount + ua.AnswerCount + ua.CommentCount > 100
),
PostsWithLinkInfo as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        pl.LinkTypeId,
        pl.RelatedPostId
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
),
DuplicateQuestions as (
    select distinct
        p.Id as QuestionId,
        p.Title,
        pl.RelatedPostId as OriginalQuestionId,
        oq.Title as OriginalQuestionTitle
    from Posts p
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3 -- Duplicate link type
    join Posts oq on oq.Id = pl.RelatedPostId and oq.PostTypeId = 1
    where p.PostTypeId = 1
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    q.Title as QuestionTitle,
    q.CreationDate as QuestionCreated,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    coalesce(pa.TotalAnswers,0) as AnswerCount,
    coalesce(pa.AvgAnswerScore,0) as AverageAnswerScore,
    coalesce(pa.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(pa.AnswersByAsker,0) as AnswersByQuestionOwner,
    coalesce(cw.CloseReasonName, 'Open') as CloseStatus,
    dup.OriginalQuestionId,
    dup.OriginalQuestionTitle,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    concat_ws(' | ',
        case when q.Tags is null then 'No Tags' else replace(replace(q.Tags, '<', ''), '>', ', ') end,
        'Score: ' || q.Score,
        'Views: ' || q.ViewCount
    ) as TagSummary,
    row_number() over (partition by u.Id order by q.CreationDate desc) as QuestionNumberByUser,
    dense_rank() over (order by q.Score desc) as QuestionScoreRank
from PostsWithCloseInfo q
left join PostAnswerStats pa on pa.QuestionId = q.Id
left join DuplicateQuestions dup on dup.QuestionId = q.Id
left join Users u on u.Id = q.OwnerUserId
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join PostsWithCloseInfo cw on cw.Id = q.Id and cw.PostHistoryTypeId = 10
where q.CreationDate >= (current_date - interval '365 days')
  and (q.Score > 10 or pa.TotalAnswers > 5)
order by QuestionScoreRank, QuestionCreated desc
limit 100;