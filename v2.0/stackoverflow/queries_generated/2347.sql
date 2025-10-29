-- {"query": "2347.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1705} 
with RecursiveTagHierarchy as (
    select 
        t.Id, 
        t.TagName, 
        t.Count, 
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1
    union all
    select 
        t2.Id, 
        t2.TagName, 
        t2.Count, 
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on r.Level < 2 and not t2.Id = any(r.Path)  -- Prevent cycles, limit depth to 2
    where t2.IsRequired = 0
),
LatestPostHistory AS (
    select ph1.*
    from PostHistory ph1
    join (
        select PostId, max(CreationDate) as MaxDate
        from PostHistory
        group by PostId
    ) ph2 on ph1.PostId = ph2.PostId and ph1.CreationDate = ph2.MaxDate
),
UserAnswerStats AS (
    select 
        u.Id as UserId,
        count(a.Id) filter (where a.Score > 5) as HighScoreAnswers,
        count(a.Id) as TotalAnswers,
        sum(a.Score) as SumScore,
        max(a.Score) as MaxScore,
        percentile_cont(0.5) within group (order by a.Score) as MedianScore,
        count(distinct a.ParentId) as QuestionsAnsweredCount
    from Users u
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id
),
UserBadgeSummary as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TopQuestionsWithCommentsAndVotes AS (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        coalesce(vc.UpVotes, 0) as UpVotesCount,
        coalesce(vc.DownVotes, 0) as DownVotesCount,
        count(c.Id) as CommentCount
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select 
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.PostId
    ) vc on vc.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, u.DisplayName, vc.UpVotes, vc.DownVotes
    having p.Score > 10 and count(c.Id) > 2
),
AcceptedAnswerWithUserReputation AS (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.Score as AnswerScore, u.Id as UserId, u.Reputation, 
           a.CreationDate, a.Body, a.OwnerDisplayName
    from Posts a
    join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
UserTagActivity as (
    select 
        u.Id as UserId,
        unnest(string_to_array(trim(both '<>' from coalesce(p.Tags, '')), '><')) as Tag,
        count(*) as PostsCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    group by u.Id, Tag
),
UserTopTags as (
    select UserId, Tag, PostsCount,
           row_number() over (partition by UserId order by PostsCount desc) as rn
    from UserTagActivity
),
UserBestTag as (
    select UserId, Tag as BestTag
    from UserTopTags
    where rn = 1
),
CloseReasonCounts AS (
    select crt.Name as CloseReason, count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by crt.Name
),
AnswerScoresWindow AS (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        avg(a.Score) over (partition by a.ParentId) as AvgAnswerScore,
        max(a.Score) over (partition by a.ParentId) as MaxAnswerScore,
        rank() over (partition by a.ParentId order by a.Score desc) as ScoreRank
    from Posts a
    where a.PostTypeId = 2
)
select 
    q.QuestionId,
    q.Title,
    q.OwnerName,
    q.CreationDate as QuestionCreated,
    q.QuestionScore,
    q.ViewCount,
    q.UpVotesCount,
    q.DownVotesCount,
    q.CommentCount,
    aa.AnswerId as AcceptedAnswerId,
    aa.AnswerScore as AcceptedAnswerScore,
    aa.UserId as AcceptedAnswerUserId,
    ua.Reputation as AcceptedAnswerUserReputation,
    ua.DisplayName as AcceptedAnswerUserName,
    us.HighScoreAnswers,
    us.TotalAnswers,
    us.MedianScore as UserMedianAnswerScore,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ut.BestTag,
    cr.CloseReason,
    cr.CloseCount,
    string_agg(distinct rt.TagName || ':' || rt.Count::text, ', ') as RequiredPlusOptionalTags,
    greatest(q.UpVotesCount - q.DownVotesCount, 0) as NetUpVotes,
    -- Complex string expression:
    concat_ws(' | ',
        coalesce(q.Title, 'No Title'),
        'Score: ' || q.QuestionScore,
        'Views: ' || q.ViewCount,
        'Owner: ' || coalesce(q.OwnerName, 'Unknown'),
        'Accepted Answer Score: ' || coalesce(aa.AnswerScore::text, 'N/A')
    ) as Summary,
    answ.ScoreRank,
    answ.AvgAnswerScore,
    answ.MaxAnswerScore,
    case when q.ClosedDate is null then 'Open' else 'Closed' end as QuestionStatus,
    case when q.ClosedDate is null then null else EXTRACT(epoch FROM now() - q.ClosedDate)::int end as SecondsSinceClosed
from TopQuestionsWithCommentsAndVotes q
left join Posts aa on aa.Id = q.AcceptedAnswerId
left join Users ua on aa.OwnerUserId = ua.Id
left join UserAnswerStats us on ua.Id = us.UserId
left join UserBadgeSummary ubs on ua.Id = ubs.UserId
left join UserBestTag ut on ua.Id = ut.UserId
left join CloseReasonCounts cr on 1=1
left join RecursiveTagHierarchy rt on rt.Level <= 1 and rt.TagName = any(string_to_array(trim(both '<>' from coalesce(q.Tags, '')), '><'))
left join AnswerScoresWindow answ on answ.AnswerId = aa.Id
where q.ViewCount > 1000
order by q.QuestionScore desc, q.ViewCount desc
limit 50;