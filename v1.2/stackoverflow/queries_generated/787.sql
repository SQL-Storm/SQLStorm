-- {"query": "787.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1535} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        rtc.TotalAnswers + coalesce(p2.AnswerCount, 0),
        rtc.TotalViews + coalesce(p2.ViewCount, 0)
    from Tags t2
    join RecursiveTagCounts rtc on rtc.TagId <> t2.Id
    left join Posts p2 on p2.Id = t2.ExcerptPostId and p2.PostTypeId = 1
    where t2.IsModeratorOnly = 0
    and rtc.TotalViews < 1000000
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesReceived,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) as HighestBadgeClass,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id or v.PostId = p2.Id
    left join Badges b on b.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
AnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
),
TopAnswers as (
    select
        asn.AnswerId,
        asn.QuestionId,
        asn.OwnerUserId,
        asn.Score,
        asn.CreationDate,
        asn.AnswerRank,
        asn.TotalAnswers,
        q.Title as QuestionTitle,
        q.Tags
    from AnswerStats asn
    join Posts q on q.Id = asn.QuestionId
    where asn.AnswerRank <= 3
),
UserReputationWindow as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.BadgeCount,
        ua.HighestBadgeClass,
        ua.LastEditDate,
        avg(ua.Reputation) over (order by ua.Reputation rows between 4 preceding and 4 following) as AvgRepAroundUser,
        rank() over (order by ua.Reputation desc) as RepRank,
        dense_rank() over (partition by ua.HighestBadgeClass order by ua.Reputation desc) as RepRankInBadgeClass
    from UserActivity ua
    where ua.Reputation is not null
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateId,
        pl.RelatedPostId as OriginalId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserCommentSummary as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > current_timestamp - interval '30 days' then 1 else 0 end) as RecentComments,
        count(distinct c.PostId) as PostsCommentedOn
    from Comments c
    group by c.UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.UpVotesReceived,
    u.DownVotesReceived,
    u.BadgeCount,
    u.HighestBadgeClass,
    u.LastEditDate,
    urw.AvgRepAroundUser,
    urw.RepRank,
    urw.RepRankInBadgeClass,
    coalesce(ucs.CommentCount,0) as TotalComments,
    coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
    coalesce(ucs.RecentComments,0) as RecentComments,
    coalesce(ucs.PostsCommentedOn,0) as PostsCommentedOn,
    ta.AnswerId,
    ta.QuestionId,
    ta.Score as AnswerScore,
    ta.AnswerRank,
    ta.TotalAnswers,
    substring(ta.QuestionTitle from 1 for 50) || case when length(ta.QuestionTitle) > 50 then '...' else '' end as ShortQuestionTitle,
    array_to_string(string_to_array(replace(replace(ta.Tags, '<', ''), '>', ''), ' '), ', ') as TagList,
    dq.DuplicateId,
    dq.OriginalId,
    substring(dq.DuplicateTitle from 1 for 30) as DuplicateTitleShort,
    substring(dq.OriginalTitle from 1 for 30) as OriginalTitleShort,
    dq.LinkCreationDate,
    rtc.TagName,
    rtc.Count as TagUseCount,
    rtc.TotalAnswers as TagTotalAnswers,
    rtc.TotalViews as TagTotalViews
from UserActivity u
left join UserReputationWindow urw on urw.Id = u.Id
left join UserCommentSummary ucs on ucs.UserId = u.Id
left join TopAnswers ta on ta.OwnerUserId = u.Id
left join DuplicateQuestions dq on dq.DuplicateId = ta.QuestionId
left join RecursiveTagCounts rtc on rtc.TagName = any(string_to_array(replace(replace(ta.Tags, '<', ''), '>', ''), ' '))
where u.Reputation > 5000
  and (u.LastEditDate is null or u.LastEditDate < current_timestamp - interval '7 days')
order by u.Reputation desc, ta.AnswerScore desc
limit 100;