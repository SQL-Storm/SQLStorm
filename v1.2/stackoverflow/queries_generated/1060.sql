-- {"query": "1060.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1586} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Path,
        1 as Level
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Path || t.Id,
        r.Level + 1
    from Tags t
    join RecursiveTagHierarchy r on t.Id != all(r.Path)
    where t.Count > 1000 and r.Level < 3
),
RecentHighScoreQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by u.Id order by p.Score desc) as UserQuestionRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.CreationDate >= current_date - interval '180 days'
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
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
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(ph.Id) as CloseVoteCount
    from PostHistory ph
    join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
QuestionWithCloseInfo as (
    select
        q.*,
        coalesce(qcr.CloseVoteCount,0) as CloseVoteCount,
        qcr.CloseReasonName
    from RecentHighScoreQuestions q
    left join QuestionCloseReasons qcr on q.Id = qcr.PostId
),
AggregatedScores as (
    select
        p.Id,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
UserActivityRanking as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        rank() over (order by count(distinct p.Id) desc, count(distinct c.Id) desc) as ActivityRank
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    group by u.Id, u.DisplayName
),
UserQuestionAnswerStats as (
    select
        u.Id as UserId,
        count(distinct q.Id) filter (where q.PostTypeId = 1) as QuestionCount,
        count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
        avg(coalesce(q.Score,0)) filter (where q.PostTypeId = 1) as AvgQuestionScore,
        avg(coalesce(a.Score,0)) filter (where a.PostTypeId = 2) as AvgAnswerScore
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id
)
select
    q.Id as QuestionId,
    q.Title,
    q.Score as QuestionScore,
    q.ViewCount,
    q.OwnerName,
    coalesce(ans.AnswerCount, 0) as AnswerCount,
    coalesce(ans.AvgAnswerScore, 0)::numeric(10,2) as AvgAnswerScore,
    coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(ans.AnonymousAnswers, 0) as AnonymousAnswerCount,
    coalesce(ag.UpVotes, 0) as QuestionUpVotes,
    coalesce(ag.DownVotes, 0) as QuestionDownVotes,
    coalesce(ag.TotalBounty, 0) as TotalBountyAwarded,
    q.CloseVoteCount,
    q.CloseReasonName,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    ua.ActivityRank,
    ua.PostCount as UserPostCount,
    ua.CommentCount as UserCommentCount,
    uqa.QuestionCount as UserQuestionCount,
    uqa.AnswerCount as UserAnswerCount,
    uqa.AvgQuestionScore,
    uqa.AvgAnswerScore,
    string_agg(distinct pld.LinkTypeName, ', ') as LinkTypesToRelatedPosts,
    array_to_string(array_agg(distinct rth.TagName), ' > ') as RecursiveTagPath
from QuestionWithCloseInfo q
left join AnswerStats ans on q.Id = ans.QuestionId
left join AggregatedScores ag on q.Id = ag.Id
left join UserBadgeCounts bc on (select OwnerUserId from Posts where Id = q.Id) = bc.UserId
left join UserActivityRanking ua on ua.Id = (select OwnerUserId from Posts where Id = q.Id)
left join UserQuestionAnswerStats uqa on uqa.UserId = ua.Id
left join PostLinkDetails pld on pld.PostId = q.Id
left join RecursiveTagHierarchy rth on position(rth.TagName in q.Tags) > 0
where q.UserQuestionRank = 1
group by
    q.Id, q.Title, q.Score, q.ViewCount, q.OwnerName,
    ans.AnswerCount, ans.AvgAnswerScore, ans.MaxAnswerScore, ans.AnonymousAnswers,
    ag.UpVotes, ag.DownVotes, ag.TotalBounty,
    q.CloseVoteCount, q.CloseReasonName,
    bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges,
    ua.ActivityRank, ua.PostCount, ua.CommentCount,
    uqa.QuestionCount, uqa.AnswerCount, uqa.AvgQuestionScore, uqa.AvgAnswerScore
order by q.Score desc, ans.AnswerCount desc
limit 50;