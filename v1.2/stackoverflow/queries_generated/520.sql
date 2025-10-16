-- {"query": "520.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1525} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join (
        select OwnerUserId, count(*) as BadgeCount
        from Badges
        group by OwnerUserId
    ) b on b.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        join Posts p on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) v on v.OwnerUserId = u.Id
    join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
),
TopQuestions as (
    select
        rp.Id as QuestionId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.Tags,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.OwnerReputation,
        coalesce(ans.AnswerCount, 0) as AnswerCount,
        coalesce(acc.Score, 0) as AcceptedAnswerScore,
        acc.Id as AcceptedAnswerId
    from RankedPosts rp
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on ans.ParentId = rp.Id
    left join Posts acc on acc.Id = rp.AcceptedAnswerId
    where rp.PostTypeId = 1 and rp.PostRank <= 100
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
AnswerScores as (
    select
        p.ParentId as QuestionId,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        count(*) as AnswerCount
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivityWindow as (
    select
        ua.*,
        count(*) over (partition by ua.UserId order by ua.PostCreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(ua.Score) over (partition by ua.UserId order by ua.PostCreationDate range between interval '30 days' preceding and current row) as ScoreLast30Days
    from RecursiveUserActivity ua
),
FilteredUsers as (
    select distinct UserId
    from UserActivityWindow
    where PostsLast30Days >= 5 and ScoreLast30Days > 10
)
select
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score as QuestionScore,
    tq.ViewCount,
    tq.Tags,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    tq.OwnerReputation,
    coalesce(qc.CommentCount, 0) as CommentCount,
    qc.LastCommentDate,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    pls.DuplicateCount,
    pls.LinkedCount,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.AnswerCount,
    case
        when tq.AcceptedAnswerId is not null then 'Accepted'
        else 'No Accepted Answer'
    end as AcceptedAnswerStatus,
    case
        when strpos(tq.Tags, 'sql') > 0 then 'Contains SQL Tag'
        else 'No SQL Tag'
    end as SqlTagPresence,
    (select count(*)
     from Comments c2
     where c2.PostId = tq.QuestionId
       and c2.CreationDate > tq.CreationDate + interval '30 days') as CommentsAfter30Days,
    (select count(*)
     from Votes v2
     join VoteTypes vt2 on v2.VoteTypeId = vt2.Id
     where v2.PostId = tq.QuestionId and vt2.Name = 'UpMod' and v2.CreationDate > tq.CreationDate + interval '7 days') as UpVotesAfter1Week
from TopQuestions tq
left join QuestionComments qc on qc.PostId = tq.QuestionId
left join UserBadgeSummary ubs on ubs.UserId = tq.OwnerUserId
left join PostLinkSummary pls on pls.PostId = tq.QuestionId
left join AnswerScores ans on ans.QuestionId = tq.QuestionId
where tq.OwnerUserId in (select UserId from FilteredUsers)
  and (tq.Score > 10 or ans.MaxAnswerScore > 20)
order by tq.Score desc, ans.MaxAnswerScore desc, qc.CommentCount desc
limit 50;