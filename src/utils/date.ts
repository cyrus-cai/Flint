export const getCurrentWeek = () => {
    const now = new Date()
    const start = new Date(now.getFullYear(), 0, 1)
    const firstMonday = new Date(start)

    // 调整到第一个星期一
    while (firstMonday.getDay() !== 1) {
        firstMonday.setDate(firstMonday.getDate() + 1)
    }

    const diff = now.getTime() - firstMonday.getTime()
    const oneWeek = 7 * 24 * 60 * 60 * 1000
    const weekNumber = Math.floor(diff / oneWeek) + 1

    return `${now.getFullYear()}W${weekNumber.toString().padStart(2, '0')}`
}