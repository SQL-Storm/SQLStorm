-- {"query": "978.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1964} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1
    union all
    select
        tg.Id,
        tg.TagName,
        tg.Count,
        tg.IsModeratorOnly,
        tg.IsRequired,
        r.Level + 1,
        r.Path || tg.Id
    from Tags tg
    join PostLinks pl on pl.PostId = tg.WikiPostId
    join Posts p on pl.RelatedPostId = p.Id and p.PostTypeId = 1 -- linked question
    join RecursiveTagHierarchy r on r.Id = tg.Id
    where not tg.Id = any(r.Path) -- avoid cycles
),
BadgesAgg as (
    select 
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct case when b.Date >= current_date - interval '30 day' then b.Id end) as RecentBadgesLastMonth
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(pq.QuestionCount,0) as QuestionCount,
        coalesce(pa.AnswerCount,0) as AnswerCount,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(c.CommentCount,0) as CommentCount,
        ba.GoldBadges,
        ba.SilverBadges,
        ba.BronzeBadges,
        ba.RecentBadgesLastMonth,
        case when u.WebsiteUrl is null or length(trim(u.WebsiteUrl)) = 0 then 'N/A' else u.WebsiteUrl end as CleanWebsiteUrl,
        u.CreationDate,
        u.LastAccessDate
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts 
        where PostTypeId = 1 and OwnerUserId is not null
        group by OwnerUserId
    ) pq on pq.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts 
        where PostTypeId = 2 and OwnerUserId is not null
        group by OwnerUserId
    ) pa on pa.OwnerUserId = u.Id
    left join (
        select UserId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        where UserId is not null
        group by UserId
    ) v on v.UserId = u.Id
    left join (
        select UserId, count(*) as CommentCount
        from Comments
        where UserId is not null
        group by UserId
    ) c on c.UserId = u.Id
    left join BadgesAgg ba on ba.UserId = u.Id
),
TopPosts as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        Rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
),
AcceptedAnswerVotes as (
    select
        a.Id as AnswerId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesOnAcceptedAnswer,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesOnAcceptedAnswer
    from Posts a
    left join Votes v on v.PostId = a.Id and v.VoteTypeId in (2,3)
    where a.PostTypeId = 2
    group by a.Id
),
QuestionWithAcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        a.Id as AcceptedAnswerId,
        aa.UpVotesOnAcceptedAnswer,
        aa.DownVotesOnAcceptedAnswer
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join AcceptedAnswerVotes aa on aa.AnswerId = a.Id
    where q.PostTypeId = 1
),
UserRecentActivity as (
    select 
        u.Id as UserId,
        count(distinct ph.Id) as EditsLastMonth,
        count(distinct v.Id) as VotesLastMonth,
        count(distinct c.Id) as CommentsLastMonth
    from Users u
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate >= current_date - interval '30 day'
    left join Votes v on v.UserId = u.Id and v.CreationDate >= current_date - interval '30 day'
    left join Comments c on c.UserId = u.Id and c.CreationDate >= current_date - interval '30 day'
    group by u.Id
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UpVotes,
    ua.DownVotes,
    ua.CommentCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.RecentBadgesLastMonth,
    ua.CleanWebsiteUrl,
    ua.CreationDate,
    ua.LastAccessDate,
    ura.EditsLastMonth,
    ura.VotesLastMonth,
    ura.CommentsLastMonth,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.Tags as QuestionTags,
    qas.AcceptedAnswerId,
    coalesce(qas.UpVotesOnAcceptedAnswer,0) as AcceptedAnswerUpVotes,
    coalesce(qas.DownVotesOnAcceptedAnswer,0) as AcceptedAnswerDownVotes,
    -- complex string manipulation: extract first tag from question tags or fallback
    case 
        when qas.Tags is not null and length(trim(qas.Tags)) > 2 then 
            substring(qas.Tags from '\\<(.*?)\\>') 
        else 'NoTag' 
    end as FirstTagExtracted,
    -- complex NULL logic in join for last editor display name
    coalesce(
        (select ph.UserDisplayName 
         from PostHistory ph 
         where ph.PostId = qas.QuestionId and ph.PostHistoryTypeId = 4
         order by ph.CreationDate desc
         limit 1),
        'Unknown Editor') as LastEditorOnQuestion,
    -- window function example: user rank by reputation among all users
    rank() over (order by ua.Reputation desc) as ReputationRank,
    -- correlated subquery with complicated predicate: count user's badges with names containing 'gold' ignoring case and nulls
    (select count(*) from Badges b where b.UserId = ua.UserId and lower(b.Name) like '%gold%') as GoldNamedBadgesCount,
    -- complex predicate: user considered "active" if last access within 90 days AND has at least 1 recent badge OR at least 10 posts
    case 
        when ua.LastAccessDate >= current_date - interval '90 day' and (ua.RecentBadgesLastMonth > 0 or ua.QuestionCount + ua.AnswerCount >= 10) 
        then 1 else 0 end as IsActiveUser,
    -- union example: combine users with zero answers and users with zero questions (using union all to not remove duplicates)
    uZeroAnswers.UserId as ZeroAnswerUserId,
    uZeroQuestions.UserId as ZeroQuestionUserId
from UserActivity ua
left join UserRecentActivity ura on ura.UserId = ua.UserId
left join QuestionWithAcceptedAnswerStats qas on qas.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1
)
left join (
    select OwnerUserId as UserId
    from Posts
    where PostTypeId = 2
    group by OwnerUserId
    having count(*) = 0
) uZeroAnswers on uZeroAnswers.UserId = ua.UserId
left join (
    select OwnerUserId as UserId
    from Posts
    where PostTypeId = 1
    group by OwnerUserId
    having count(*) = 0
) uZeroQuestions on uZeroQuestions.UserId = ua.UserId
where ua.Reputation > 100
order by ua.Reputation desc
limit 100;