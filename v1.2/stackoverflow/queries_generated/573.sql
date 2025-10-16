-- {"query": "573.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1774} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        cast(t.TagName as varchar(1000)) as FullPath,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        concat(r.FullPath, ' > ', c.TagName),
        r.Level + 1
    from Tags c
    join RecursiveTagHierarchy r on c.Id = r.Id + 1 and c.IsModeratorOnly = 0
    where r.Level < 3
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > now() - interval '1 year'
    group by b.UserId, b.Class
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc.Gold,0) as GoldBadges,
        coalesce(ubc.Silver,0) as SilverBadges,
        coalesce(ubc.Bronze,0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        sum(vt.UpVotes) as TotalUpVotes,
        sum(vt.DownVotes) as TotalDownVotes
    from Users u
    left join (
        select UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) as Gold,
            sum(case when Class = 2 then BadgeCount else 0 end) as Silver,
            sum(case when Class = 3 then BadgeCount else 0 end) as Bronze
        from UserBadgeCounts
        group by UserId
    ) ubc on u.Id = ubc.UserId
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join (
        select p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, ubc.Gold, ubc.Silver, ubc.Bronze
),
TopQuestionsCTE as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.CreationDate > now() - interval '1 year'
),
AcceptedAnswerScores as (
    select 
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName
    from Posts q
    join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1 and a.PostTypeId = 2
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
QuestionCommentsCount as (
    select 
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
UserReputationRank as (
    select 
        Id,
        DisplayName,
        Reputation,
        rank() over (order by Reputation desc) as RepRank
    from Users
),
HighRepUsersWithBadge as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges
    from UserActivity u
    join UserBadgeCounts ubc on u.UserId = ubc.UserId
    where u.Reputation > 10000 and ubc.GoldBadges > 0
),
FinalSelection as (
    select 
        tq.Id as QuestionId,
        tq.Title,
        tq.CreationDate,
        tq.Score as QuestionScore,
        tq.ViewCount,
        tq.AnswerCount,
        coalesce(qcr.CloseReasonName, 'Open') as Status,
        coalesce(qcc.CommentCount, 0) as TotalComments,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerOwnerName,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionCount,
        ua.AnswerCount as UserAnswerCount,
        ua.AvgPostScore,
        ua.MaxPostScore,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ur.RepRank
    from TopQuestionsCTE tq
    left join AcceptedAnswerScores a on a.QuestionId = tq.Id
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
    left join QuestionCommentsCount qcc on qcc.PostId = tq.Id
    left join UserActivity ua on ua.UserId = tq.OwnerUserId
    left join UserReputationRank ur on ur.Id = tq.OwnerUserId
    where tq.rn = 1
)
select 
    fs.QuestionId,
    fs.Title,
    fs.CreationDate,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.Status,
    fs.TotalComments,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerOwnerName,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.QuestionCount,
    fs.UserAnswerCount,
    fs.AvgPostScore,
    fs.MaxPostScore,
    fs.TotalUpVotes,
    fs.TotalDownVotes,
    fs.RepRank,
    -- Complex string expression with NULL logic
    case 
        when fs.Status = 'Open' then concat('Q:', fs.Title, ' [Open]')
        when fs.Status is null then 'Status Unknown'
        else concat('Q:', fs.Title, ' [Closed: ', fs.Status, ']')
    end as QuestionSummary,
    -- Window function example: rank questions by score within status
    rank() over (partition by fs.Status order by fs.QuestionScore desc) as ScoreRankWithinStatus,
    -- Correlated subquery with EXISTS and NOT EXISTS
    exists (
        select 1 from Votes v 
        where v.PostId = fs.QuestionId and v.VoteTypeId = 2 and v.CreationDate > fs.CreationDate - interval '30 days'
    ) as HasRecentUpVotes,
    not exists (
        select 1 from PostLinks pl 
        where pl.PostId = fs.QuestionId and pl.LinkTypeId = 3
    ) as IsNotMarkedDuplicate
from FinalSelection fs
where fs.RepRank <= 500
order by fs.Status desc nulls last, fs.QuestionScore desc
limit 100;